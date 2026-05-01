# terraform.tfvars — the file where you SET variable values
# This file is environment-specific (dev.tfvars, prod.tfvars)
# NEVER commit secrets here. Use -var or environment variables for sensitive values.

# Usage:
#   terraform plan -var-file="dev.tfvars"
#   terraform plan -var-file="prod.tfvars"

environment       = "dev"
instance_count    = 2
enable_monitoring = false

availability_zones = ["eu-west-2a", "eu-west-2b"]

instance_types = {
  dev     = "t3.micro"
  staging = "t3.medium"
  prod    = "t3.large"
}

vpc_config = {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# db_password = "NEVER PUT THIS HERE"
# Instead use: export TF_VAR_db_password="mypassword"
# Or: terraform apply -var="db_password=$DB_PASS"
