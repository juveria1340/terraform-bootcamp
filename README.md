# Terraform Bootcamp — Juveria's IBM DevSecOps Prep

## Your Learning Path (4 weeks)

| Week | Focus | Goal |
|------|-------|------|
| 1 | Core HCL syntax, providers, resources | Write & understand any `.tf` file |
| 2 | Variables, outputs, modules, state | Build reusable, production-grade IaC |
| 3 | AWS + Azure security patterns | Align with IBM JD cloud security requirements |
| 4 | Interview scenarios + live walkthroughs | Ace the technical round |

## How to use this bootcamp

Each folder has:
- `main.tf` — real Terraform code to study and run
- `NOTES.md` — concept explanation + "why this matters for IBM"
- `interview_qs.md` — questions you WILL be asked, with model answers

## Setup on your laptop

```bash
# Install Terraform
brew install terraform          # Mac
winget install HashiCorp.Terraform  # Windows

# Verify
terraform version

# Each lab
cd 01-basics
terraform init
terraform validate
terraform plan   # reads code, shows what WOULD happen (no real infra needed with mock provider)
```

## Core Terraform Commands (memorise these)

| Command | What it does | When to use |
|---------|-------------|-------------|
| `terraform init` | Downloads providers, sets up backend | First time, or after adding providers |
| `terraform validate` | Checks HCL syntax | Before every commit |
| `terraform plan` | Shows what WILL change | Before every apply |
| `terraform apply` | Creates/updates real infra | After reviewing plan |
| `terraform destroy` | Tears down infra | Cleanup / teardown |
| `terraform fmt` | Auto-formats your `.tf` files | Before every commit |
| `terraform state list` | Lists tracked resources | Debugging state issues |
| `terraform import` | Imports existing infra into state | Onboarding legacy infra |
| `terraform output` | Shows output values | Getting IPs, IDs after apply |
