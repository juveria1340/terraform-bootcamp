# =============================================================
# MODULE 6: CI/CD Security Pipeline Pattern
# IBM JD: "Integrate automated security scanning (SAST/DAST/SCA),
# secrets management, policy enforcement as part of the delivery workflow"
#
# This shows Terraform for the pipeline INFRASTRUCTURE itself
# =============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

# =============================================================
# CodePipeline — the pipeline infrastructure itself in Terraform
# This is what IBM means by "security embedded in CI/CD"
# =============================================================

resource "aws_codepipeline" "secure_deploy" {
  name     = "ibm-secure-deploy"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"

    # Encrypt pipeline artifacts
    encryption_key {
      id   = aws_kms_key.pipeline.arn
      type = "KMS"
    }
  }

  # STAGE 1: Source — pull from Git
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "ibm-org/platform-iac"
        BranchName       = "main"
      }
    }
  }

  # STAGE 2: SAST — Static analysis before anything runs
  stage {
    name = "SecurityScan"
    action {
      name             = "SAST-Checkov"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["scan_output"]

      configuration = {
        ProjectName = aws_codebuild_project.checkov_scan.name
      }
    }
  }

  # STAGE 3: Plan — terraform plan with approval gate
  stage {
    name = "TerraformPlan"
    action {
      name             = "Plan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["plan_output"]

      configuration = {
        ProjectName = aws_codebuild_project.terraform_plan.name
      }
    }
  }

  # STAGE 4: Manual approval — human reviews plan before apply
  # Interview Q: "How do you prevent accidental infra changes?"
  # Answer: Approval gates + required reviewers
  stage {
    name = "Approval"
    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = aws_sns_topic.pipeline_approval.arn
        CustomData      = "Review terraform plan before applying to production"
      }
    }
  }

  # STAGE 5: Apply — only runs after human approval
  stage {
    name = "TerraformApply"
    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["plan_output"]

      configuration = {
        ProjectName = aws_codebuild_project.terraform_apply.name
      }
    }
  }
}

# =============================================================
# CodeBuild project for Checkov SAST scanning
# This is the "security scanning embedded in pipeline" from IBM JD
# =============================================================

resource "aws_codebuild_project" "checkov_scan" {
  name         = "ibm-checkov-scan"
  description  = "SAST security scanning with Checkov"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false   # Security: don't give Docker privilege unless needed

    environment_variable {
      name  = "CHECKOV_OUTPUT_FORMAT"
      value = "sarif"   # Standard security format
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = yamlencode({
      version = "0.2"
      phases = {
        install = {
          commands = [
            "pip install checkov",
            "pip install checkov[all]"
          ]
        }
        build = {
          commands = [
            # Run Checkov — fail pipeline if HIGH severity issues found
            "checkov -d . --framework terraform --output sarif --output-file-path checkov-results.sarif",
            # Also check for secrets in code
            "checkov -d . --framework secrets --output cli",
            # Soft fail on MEDIUM, hard fail on HIGH/CRITICAL
            "checkov -d . --framework terraform --check HIGH,CRITICAL"
          ]
        }
        post_build = {
          commands = [
            "echo 'Security scan complete'"
          ]
        }
      }
      artifacts = {
        files = ["checkov-results.sarif"]
      }
    })
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/ibm-checkov"
      stream_name = "scan-results"
    }
  }
}

# CodeBuild for terraform plan
resource "aws_codebuild_project" "terraform_plan" {
  name         = "ibm-terraform-plan"
  service_role = aws_iam_role.codebuild.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "hashicorp/terraform:1.6"   # Pin specific Terraform version
    type         = "LINUX_CONTAINER"

    environment_variable {
      name  = "TF_WORKSPACE"
      value = "prod"
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = yamlencode({
      version = "0.2"
      phases = {
        build = {
          commands = [
            "terraform init",
            "terraform validate",
            "terraform plan -out=tfplan -input=false",
            # Save plan as readable text for the approval reviewer
            "terraform show -no-color tfplan > tfplan.txt"
          ]
        }
      }
      artifacts = {
        files = ["tfplan", "tfplan.txt"]
      }
    })
  }
}

resource "aws_codebuild_project" "terraform_apply" {
  name         = "ibm-terraform-apply"
  service_role = aws_iam_role.codebuild.arn

  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "hashicorp/terraform:1.6"
    type         = "LINUX_CONTAINER"
  }

  source {
    type = "CODEPIPELINE"
    buildspec = yamlencode({
      version = "0.2"
      phases = {
        build = {
          commands = [
            "terraform init",
            "terraform apply -auto-approve tfplan"
          ]
        }
      }
    })
  }
}

# Supporting resources
resource "aws_kms_key" "pipeline" {
  description             = "Pipeline artifact encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket        = "ibm-pipeline-artifacts"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket                  = aws_s3_bucket.pipeline_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_sns_topic" "pipeline_approval" {
  name = "ibm-pipeline-approval"
}

resource "aws_codestarconnections_connection" "github" {
  name          = "ibm-github"
  provider_type = "GitHub"
}

# IAM roles (simplified for readability)
resource "aws_iam_role" "codepipeline" {
  name               = "ibm-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "codepipeline.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role" "codebuild" {
  name               = "ibm-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })
}
