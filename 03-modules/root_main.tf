# =============================================================
# ROOT MODULE — calls the VPC module
# This is what you'd write in a real IaC repo
# Notice: IBM JD says "reusable libraries" — this is exactly that
# =============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # REMOTE STATE — critical for team environments
  # Interview Q: "Where do you store Terraform state?"
  # NEVER local state in production. Use S3 + DynamoDB for locking.
  backend "s3" {
    bucket         = "ibm-terraform-state-prod"
    key            = "networking/vpc/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true                           # State file encryption
    dynamodb_table = "ibm-terraform-state-lock"    # Prevents concurrent applies
  }
}

provider "aws" {
  region = "eu-west-2"

  # Assume an IAM role — NEVER use root/personal credentials in pipelines
  # Interview Q: "How do Terraform pipelines authenticate to AWS?"
  # Answer: IAM roles via assume_role (not access keys)
  assume_role {
    role_arn = "arn:aws:iam::123456789012:role/TerraformExecutionRole"
  }

  default_tags {
    tags = {
      ManagedBy  = "terraform"
      Repository = "github.com/ibm/platform-iac"
    }
  }
}

# -------------------------------------------------------
# CALLING THE VPC MODULE
# Source can be: local path, Git URL, Terraform Registry
# -------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"   # local path in real repo

  # Or from Terraform Registry:
  # source  = "terraform-aws-modules/vpc/aws"
  # version = "~> 5.0"

  name = "ibm-platform"
  cidr = "10.0.0.0/16"

  azs = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]

  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true

  tags = {
    Environment = "prod"
    Project     = "ibm-platform"
    CostCenter  = "eng-001"
  }
}

# -------------------------------------------------------
# USE MODULE OUTPUTS to create other resources
# -------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "ibm-app-sg"
  description = "Security group for application servers"
  vpc_id      = module.vpc.vpc_id   # ← reference module output

  # INBOUND: only HTTPS from anywhere (not HTTP)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS inbound"
  }

  # OUTBOUND: restrict to specific needs
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound only"
  }

  tags = {
    Name = "ibm-app-sg"
  }
}

# -------------------------------------------------------
# ROOT OUTPUTS — expose what other teams need
# -------------------------------------------------------
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}
