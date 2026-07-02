# AGENTS.md

## Cursor Cloud specific instructions

This repository is a **Terraform Infrastructure-as-Code module stack** (`terraform-aws-rds`) for provisioning AWS RDS instances. There is **no application server, frontend, or GUI** — "running" it means executing Terraform workflows. The authoritative command list lives in the `justfile` (`just init | fmt | validate | plan | apply | destroy | docs`).

### Tooling
Installed at the system level (persisted in the VM snapshot): `terraform`, `just`, `aws` (AWS CLI v2), `terraform-docs`, `jq`. The startup update script runs `terraform init -input=false -upgrade` to refresh providers/modules.

### Offline dev/verification loop (no AWS account needed)
This is the local/CI verification path and works without credentials:
- `just init` — `terraform init` (downloads `hashicorp/aws` provider).
- `just validate` — `terraform validate` (builds + type-checks the whole module graph).
- `terraform fmt -check -recursive` — lint check. Note: `just fmt` rewrites files in place; two files (`modules/rds_instance/variables.tf`, `modules/rds_rollback/variables.tf`) are currently not `fmt`-clean in the repo.

### Running `plan` / `apply` requires live AWS
- `just plan` / `just apply` need **real AWS credentials** AND **pre-existing VPC + DB subnet group + security groups** (looked up by name in `modules/rds_networking_data`). They cannot fully run offline.
- Gotcha: the AWS provider (v6) validates credentials via STS `GetCallerIdentity` **even during `plan`**, so `terraform plan` fails immediately without valid credentials — not just at `apply`.
- To smoke-test resource planning offline (parameter/option groups only), you can pass `-var 'networking_enabled=false' -var 'db_instance_enabled=false'` and add a temporary `*_override.tf` provider block with `skip_credentials_validation/skip_requesting_account_id/skip_metadata_api_check = true`. This is experimentation only — delete the override before committing (it is not gitignored).

### Required variables (no defaults)
`vpc_id`, `db_subnet_group_name`, `security_group_names`, `db_username`, `db_password` must be supplied via a `terraform.tfvars` (gitignored; copy from `terraform.tfvars.example`) or `-var` flags.

### Notes
- The `justfile` sets `set dotenv-load := true`, which optionally loads a `.env` (gitignored); it is not required.
- State is local by default (no remote backend configured); `.terraform/`, `*.tfstate`, `*.tfvars`, and plan files (`plan`, `*.plan`, `destroy`) are gitignored.
