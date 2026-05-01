# =============================================================
# MODULE 1: Terraform Basics
# Concept: Provider, Resource, Data Source, Locals
# Real-world context: Spin up an EC2 instance (like a VM in Bosch's pipeline infra)
# =============================================================

# -------------------------------------------------------------
# 1. TERRAFORM BLOCK — tells Terraform which providers to use
# This is always your first block. Think of providers as plugins.
# -------------------------------------------------------------
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"   # "~> 5.0" means >=5.0, <6.0
    }
  }
}

# -------------------------------------------------------------
# 2. PROVIDER BLOCK — configures the plugin (AWS in this case)
# In real IBM work: region comes from a variable, not hardcoded
# -------------------------------------------------------------
provider "aws" {
  region = "eu-west-2"   # London — relevant for UK visa jobs!
}

# -------------------------------------------------------------
# 3. DATA SOURCE — reads EXISTING infra (doesn't create anything)
# Use case: Find the latest Amazon Linux 2 AMI dynamically
# Interview Q: "What's the difference between resource and data source?"
# Answer: resource CREATES, data source READS
# -------------------------------------------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# -------------------------------------------------------------
# 4. LOCALS — reusable values within a module
# Think of them like constants in code
# Interview Q: "locals vs variables?" 
# Answer: locals are computed internally, vars come from outside
# -------------------------------------------------------------
locals {
  environment = "dev"
  app_name    = "ibm-demo"

  # Common tags — IBM will always ask about tagging strategy
  common_tags = {
    Environment = local.environment
    Project     = local.app_name
    ManagedBy   = "terraform"
    Owner       = "platform-team"
    CostCenter  = "eng-001"
  }
}

# -------------------------------------------------------------
# 5. RESOURCE — creates real infrastructure
# This EC2 instance represents a Jenkins build agent
# -------------------------------------------------------------
resource "aws_instance" "build_agent" {
  ami           = data.aws_ami.amazon_linux.id   # from data source above
  instance_type = "t3.medium"

  # Security: no public IP on build agents (private subnet only)
  associate_public_ip_address = false

  # Root volume — encrypted at rest (IBM security requirement)
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true   # ALWAYS true in secure environments
    delete_on_termination = true
  }

  # Merge common tags with resource-specific tags
  tags = merge(local.common_tags, {
    Name = "${local.app_name}-build-agent"
    Role = "ci-cd"
  })
}

# -------------------------------------------------------------
# 6. OUTPUT — exposes values after apply
# Like a return value from a function
# Interview Q: "How do you share values between modules?"
# Answer: outputs + module references
# -------------------------------------------------------------
output "build_agent_id" {
  description = "EC2 instance ID of the build agent"
  value       = aws_instance.build_agent.id
}

output "build_agent_private_ip" {
  description = "Private IP of build agent (no public IP for security)"
  value       = aws_instance.build_agent.private_ip
}
