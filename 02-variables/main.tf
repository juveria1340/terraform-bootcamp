# =============================================================
# MODULE 2: Variables, Validation & Outputs
# Concept: Input variables, type constraints, validation rules
# IBM relevance: Reusable configs across dev/staging/prod
# =============================================================

# -------------------------------------------------------------
# VARIABLE TYPES — string, number, bool, list, map, object
# -------------------------------------------------------------

# Simple string with default
variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"

  # VALIDATION — prevent bad inputs at plan time
  # Interview Q: "How do you enforce standards in Terraform?"
  # This is one answer — validation blocks
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# Number variable
variable "instance_count" {
  type        = number
  description = "Number of EC2 instances to create"
  default     = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "Instance count must be between 1 and 10."
  }
}

# Boolean
variable "enable_monitoring" {
  type        = bool
  description = "Enable detailed CloudWatch monitoring"
  default     = true
}

# List of strings
variable "availability_zones" {
  type        = list(string)
  description = "AZs to deploy into"
  default     = ["eu-west-2a", "eu-west-2b"]
}

# Map — key-value pairs of the same type
variable "instance_types" {
  type        = map(string)
  description = "Instance type per environment"
  default = {
    dev     = "t3.micro"
    staging = "t3.medium"
    prod    = "t3.large"
  }
}

# Object — structured, typed map (most powerful)
variable "vpc_config" {
  type = object({
    cidr_block           = string
    enable_dns_hostnames = bool
    enable_dns_support   = bool
  })
  description = "VPC configuration object"
  default = {
    cidr_block           = "10.0.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support   = true
  }
}

# Sensitive variable — value is hidden in plan output
# Interview Q: "How do you handle secrets in Terraform?"
# Answer 1: sensitive = true (hides in output)
# Answer 2: Use AWS Secrets Manager / HashiCorp Vault (better!)
# Answer 3: Never hardcode secrets in .tf files
variable "db_password" {
  type        = string
  description = "RDS database password — fetch from Secrets Manager in prod"
  sensitive   = true   # Won't appear in terraform plan output
}

# -------------------------------------------------------------
# LOCALS — computed from variables
# -------------------------------------------------------------
locals {
  # Select instance type based on environment variable
  selected_instance_type = var.instance_types[var.environment]

  # Build a name prefix used consistently across all resources
  name_prefix = "ibm-${var.environment}"

  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -------------------------------------------------------------
# RESOURCES using variables
# -------------------------------------------------------------
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

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_config.cidr_block
  enable_dns_hostnames = var.vpc_config.enable_dns_hostnames
  enable_dns_support   = var.vpc_config.enable_dns_support

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# count — create N copies of a resource
resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  availability_zone = var.availability_zones[count.index]

  # Subnet CIDR — offset by count index
  cidr_block = cidrsubnet(var.vpc_config.cidr_block, 8, count.index)

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${count.index + 1}"
    Tier = "public"
  })
}

# for_each — create resources from a map (preferred over count for named resources)
# Interview Q: "count vs for_each — when do you use each?"
# count: ordered list, use for identical resources
# for_each: named map, use when each resource has a unique identity
resource "aws_subnet" "private" {
  for_each = toset(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  availability_zone = each.value
  cidr_block        = cidrsubnet(var.vpc_config.cidr_block, 8, index(var.availability_zones, each.value) + 10)

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${each.value}"
    Tier = "private"
  })
}

# -------------------------------------------------------------
# OUTPUTS
# -------------------------------------------------------------
output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Map of AZ -> private subnet ID"
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }
}
