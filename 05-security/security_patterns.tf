# =============================================================
# MODULE 5: Security Patterns in Terraform
# This maps DIRECTLY to IBM JD requirements:
# - Secrets management
# - Policy enforcement
# - Base image hardening
# - Runtime protection
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
# PATTERN 1: SECRETS MANAGEMENT
# Interview Q: "How do you manage secrets in Terraform?"
# WRONG: variable "db_pass" { default = "mypassword123" }
# RIGHT: Fetch from AWS Secrets Manager at runtime
# =============================================================

data "aws_secretsmanager_secret" "db_credentials" {
  name = "/ibm/prod/db/credentials"
}

data "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = data.aws_secretsmanager_secret.db_credentials.id
}

locals {
  # Parse the JSON secret into a usable map
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.db_credentials.secret_string)
}

# Now use: local.db_creds["username"] and local.db_creds["password"]

# =============================================================
# PATTERN 2: SECURE S3 BUCKET
# Common interview scenario: "write a secure S3 bucket"
# All these settings are expected in IBM's cloud security posture
# =============================================================

resource "aws_s3_bucket" "artifacts" {
  bucket        = "ibm-platform-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = false   # prod buckets should NOT be easily destroyed
}

data "aws_caller_identity" "current" {}

# Block ALL public access — non-negotiable for secure environments
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning — object recovery + audit trail
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt at rest using AWS KMS (customer-managed key = more control)
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true   # Reduces KMS API calls (cost saving)
  }
}

# KMS key for S3 encryption
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 artifact encryption"
  deletion_window_in_days = 30      # 30-day safety window before permanent deletion
  enable_key_rotation     = true    # Rotate key material annually (compliance requirement)

  tags = {
    Purpose = "s3-encryption"
  }
}

# Enforce HTTPS only — reject HTTP requests
resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Enable access logging (audit trail — IBM will ask about this)
resource "aws_s3_bucket_logging" "artifacts" {
  bucket        = aws_s3_bucket.artifacts.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/"
}

resource "aws_s3_bucket" "logs" {
  bucket = "ibm-platform-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================
# PATTERN 3: LEAST PRIVILEGE IAM ROLE
# Interview Q: "How do you implement least privilege in AWS?"
# =============================================================

# Assume role policy — who CAN assume this role
data "aws_iam_policy_document" "terraform_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    # Condition: only from specific VPC (extra restriction)
    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpc"
      values   = ["vpc-0abc123"]
    }
  }
}

resource "aws_iam_role" "app_role" {
  name               = "ibm-app-role"
  assume_role_policy = data.aws_iam_policy_document.terraform_assume_role.json

  # Force MFA for console access (not API)
  tags = {
    ManagedBy = "terraform"
  }
}

# Permissions policy — what this role CAN do (minimum needed)
data "aws_iam_policy_document" "app_permissions" {
  # Only allow reading specific secrets
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      "arn:aws:secretsmanager:eu-west-2:*:secret:/ibm/prod/*"
    ]
  }

  # Only allow writing to specific S3 prefix
  statement {
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/uploads/*"]
  }

  # Explicit deny — can't delete anything even if other policies allow
  statement {
    effect    = "Deny"
    actions   = ["s3:DeleteObject", "s3:DeleteBucket"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "app_policy" {
  name   = "ibm-app-policy"
  policy = data.aws_iam_policy_document.app_permissions.json
}

resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app_role.name
  policy_arn = aws_iam_policy.app_policy.arn
}

# =============================================================
# PATTERN 4: RDS with encryption + no public access
# Interview scenario: "Secure a database in AWS with Terraform"
# =============================================================

resource "aws_db_instance" "app" {
  identifier = "ibm-app-db"

  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.medium"

  allocated_storage     = 20
  max_allocated_storage = 100   # Auto-scaling storage

  db_name  = "appdb"
  username = local.db_creds["username"]
  password = local.db_creds["password"]

  # SECURITY SETTINGS
  publicly_accessible    = false        # NEVER true in prod
  storage_encrypted      = true         # Encrypt at rest
  kms_key_id            = aws_kms_key.s3.arn
  deletion_protection    = true         # Can't delete without disabling this first
  skip_final_snapshot    = false        # Take snapshot before deletion
  final_snapshot_identifier = "ibm-app-db-final-snapshot"
  backup_retention_period = 7           # 7 days of automated backups
  multi_az               = true         # High availability

  # Audit logging
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = {
    Name      = "ibm-app-db"
    Encrypted = "true"
  }
}
