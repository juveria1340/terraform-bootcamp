# =============================================================
# IBM INTERVIEW SCENARIOS — Terraform
# These are REAL questions asked at DevSecOps / Platform Engineer interviews
# Each has: the question, what they're testing, model answer, code snippet
# =============================================================

# ──────────────────────────────────────────────────────────────
# SCENARIO 1: The State File Disaster
# "A colleague ran terraform apply manually and now the state is
# out of sync with the real infrastructure. How do you fix it?"
# ──────────────────────────────────────────────────────────────
#
# What they're testing: State management knowledge, incident handling
#
# Model answer:
# "First, I'd run terraform plan to see the drift — what Terraform
# thinks exists vs what actually exists in AWS. Then I have a few options:
#
# 1. terraform import — import the manually created resource into state
# 2. terraform state rm — remove stale references from state
# 3. If state is badly corrupted, restore from the S3 versioned backup
#
# To prevent this: enforce pipeline-only applies using IAM. Revoke direct
# AWS Console write permissions from developers. All changes go through Git."
#
# Key commands to know:
#   terraform state list                        — see all tracked resources
#   terraform state show aws_s3_bucket.my_bucket — inspect a specific resource
#   terraform state rm aws_s3_bucket.old_bucket  — remove from state (not AWS)
#   terraform import aws_s3_bucket.existing mybucket-name — add to state
#   terraform refresh                            — sync state with real world

# ──────────────────────────────────────────────────────────────
# SCENARIO 2: The Locked State
# "Your pipeline failed mid-apply and now nobody can run terraform.
# You get: Error acquiring the state lock"
# ──────────────────────────────────────────────────────────────
#
# What they're testing: DynamoDB locking knowledge, recovery process
#
# Model answer:
# "The state is locked via DynamoDB to prevent concurrent applies.
# When a pipeline fails mid-apply, the lock isn't released.
# 
# Resolution:
# 1. Check if any apply is actually running (check pipeline logs)
# 2. If not, force-unlock using the lock ID from the error message:
#    terraform force-unlock <LOCK_ID>
# 3. Run terraform plan to check the partial state before any reapply
#
# Prevention: Set pipeline timeouts and add lock TTLs.
# Never force-unlock while an apply might actually be running."
#
# Lock ID is in the error message:
# Error: Error acquiring the state lock
# Lock Info: ID = a1b2c3d4-...

# ──────────────────────────────────────────────────────────────
# SCENARIO 3: Destroy Production Without Wanting To
# "How do you prevent terraform destroy from accidentally
# wiping a production database?"
# ──────────────────────────────────────────────────────────────

# Prevention #1: lifecycle prevent_destroy
resource "aws_db_instance" "production" {
  identifier = "prod-database"
  # ... other config ...
  instance_class = "db.t3.medium"
  engine         = "postgres"
  engine_version = "15.4"
  username       = "admin"
  password       = "changeme"
  allocated_storage = 20

  lifecycle {
    prevent_destroy = true    # terraform destroy will ERROR on this resource
    
    # Also: ignore changes to fields that ops team might change manually
    ignore_changes = [
      engine_version,    # Ignore manual minor version upgrades
    ]
  }
}

# Prevention #2: deletion_protection (AWS-level, not Terraform-level)
resource "aws_db_instance" "production_v2" {
  identifier         = "prod-database-v2"
  instance_class     = "db.t3.medium"
  engine             = "postgres"
  engine_version     = "15.4"
  username           = "admin"
  password           = "changeme"
  allocated_storage  = 20

  deletion_protection = true   # Can't delete from AWS Console either
}

# Prevention #3: Workspace + conditional logic
# Never apply prod workspace from local machine
# variable "environment" {}
# locals {
#   is_prod = var.environment == "prod"
# }
# Then use -target sparingly and only in break-glass scenarios

# ──────────────────────────────────────────────────────────────
# SCENARIO 4: Managing Secrets Without Exposing Them
# "Walk me through how you'd manage database credentials
# in a Terraform-managed AWS environment"
# ──────────────────────────────────────────────────────────────
#
# Model answer (3-tier approach):
#
# Tier 1: CREATE the secret in Secrets Manager via Terraform
# But the actual VALUE is set manually or via pipeline secret

resource "aws_secretsmanager_secret" "db_creds" {
  name                    = "/ibm/prod/db/credentials"
  recovery_window_in_days = 30   # 30-day recovery before permanent deletion

  # Rotate automatically every 30 days
  # rotation is set up separately with a Lambda
}

# Terraform creates the SECRET OBJECT but NOT the value
# Value is set via: aws secretsmanager put-secret-value ...
# Or via pipeline: using GitHub Actions secrets → aws CLI

# Tier 2: APPLICATION reads secret at runtime (not at deploy time)
data "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = aws_secretsmanager_secret.db_creds.id
}
# Use: jsondecode(data.aws_secretsmanager_secret_version.db_creds.secret_string)

# Tier 3: .gitignore and .terraformignore 
# NEVER commit: *.tfvars files with real values, terraform.tfstate, .terraform/

# ──────────────────────────────────────────────────────────────
# SCENARIO 5: Refactoring Monolith State
# "You've inherited a 2000-line main.tf with everything in one file.
# How do you safely break it into modules?"
# ──────────────────────────────────────────────────────────────
#
# Model answer:
# "I'd do this incrementally without destroying and recreating resources:
#
# Step 1: Create the module structure with the same resource definitions
# Step 2: Use 'terraform state mv' to move resources into module namespace
#   terraform state mv aws_vpc.main module.vpc.aws_vpc.this
# Step 3: Run terraform plan — should show NO changes (just refactored)
# Step 4: If plan shows changes, fix variable/output wiring before applying
# Step 5: Commit and merge
#
# Key: terraform state mv is safe — it doesn't touch real AWS resources.
# It just renames the resource address in the state file."

# ──────────────────────────────────────────────────────────────
# SCENARIO 6: Multi-Environment Strategy
# "How do you manage dev, staging, and prod with Terraform?"
# ──────────────────────────────────────────────────────────────
#
# Option A: Workspaces (simpler, same backend)
# terraform workspace new staging
# terraform workspace select prod
# Use: terraform.workspace in code
#
# Option B: Separate state per environment (recommended for isolation)
# environments/
#   dev/
#     backend.tf  → s3://state-bucket/dev/terraform.tfstate
#     main.tf
#   prod/
#     backend.tf  → s3://state-bucket/prod/terraform.tfstate
#     main.tf
#
# Option C: Terragrunt (DRY wrapper around Terraform)
# IBM may use this — worth knowing it exists
#
# IBM Answer: "I'd use separate state files per environment stored in S3,
# with IAM roles that restrict which pipeline can access which environment.
# Dev pipeline can't touch prod state. Code reused via shared modules."

# ──────────────────────────────────────────────────────────────
# SCENARIO 7: Checkov finding in the pipeline
# "Your security scan flagged CKV_AWS_18 on your S3 bucket.
# What do you do?"
# ──────────────────────────────────────────────────────────────
#
# CKV_AWS_18 = S3 bucket should have access logging enabled
#
# Fix it:
resource "aws_s3_bucket" "example" {
  bucket = "ibm-example-bucket"
}

resource "aws_s3_bucket_logging" "example" {
  bucket        = aws_s3_bucket.example.id
  target_bucket = "ibm-access-logs-bucket"   # separate logging bucket
  target_prefix = "ibm-example-bucket/"
}

# Or if it's a false positive in a non-prod environment, suppress it:
# checkov:skip=CKV_AWS_18:Access logging not required for dev artifacts bucket
#
# Model answer:
# "I'd look up the check ID, understand the security principle behind it
# (in this case, audit trail for S3 access), fix it with the logging resource,
# and update the module template so all future buckets comply by default.
# For genuine false positives, I'd add a documented skip with justification."

# ──────────────────────────────────────────────────────────────
# COMMON TERRAFORM INTERVIEW QUESTIONS (Quick Answers)
# ──────────────────────────────────────────────────────────────
#
# Q: What is Terraform state and why is it needed?
# A: State is a JSON file mapping Terraform config to real infrastructure.
#    Needed because cloud APIs don't store "this was made by Terraform."
#    State enables plan to show what WILL change vs what EXISTS.
#
# Q: count vs for_each?
# A: count = indexed list (0,1,2...) — resources become list items.
#    for_each = named map/set — resources have stable keys.
#    Prefer for_each: deleting item 1 of 3 with count shifts indices.
#    With for_each, deleting one key doesn't affect others.
#
# Q: What happens if you delete a resource from main.tf?
# A: terraform plan shows it will be DESTROYED.
#    terraform apply removes it from AWS and state.
#    Use lifecycle.prevent_destroy to block accidental destruction.
#
# Q: How do you handle Terraform version upgrades in a team?
# A: Pin versions in terraform block (required_version = "~> 1.6").
#    Use tfenv or asdf to manage multiple versions locally.
#    Upgrade in dev first, test all plans show no unexpected changes.
#
# Q: What is a Terraform provider?
# A: A plugin that talks to a specific API (AWS, Azure, GitHub, etc.).
#    Written in Go by HashiCorp or community. 
#    Provider = translator between HCL config and API calls.
#
# Q: How do you test Terraform code?
# A: terraform validate — syntax check
#    checkov / tfsec — security scanning (SAST)
#    terraform plan — dry run
#    Terratest (Go) — integration tests that create real infra
#    Conftest / OPA — policy testing
