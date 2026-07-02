# AGENTS.md

Development guide for **`terraform-aws-rds`** — a Terraform module stack for provisioning AWS RDS instances (SQL Server / MySQL / PostgreSQL). This is Infrastructure-as-Code: there is **no application server, frontend, or GUI**; "running" it means executing Terraform workflows. For module usage and the full variable reference, see [`README.md`](./README.md).

## Prerequisites

Required CLIs: `terraform` (>= 1.0), `just`, `aws` (AWS CLI v2), `terraform-docs`, `jq`.

Tool versions are intended to be managed with [`mise`](https://mise.jdx.dev/): once a `mise.toml` is committed, run `mise install` to provision the toolchain. Until then, install the CLIs directly. **Do not install or change dependencies without explicit authorization.**

## Commands

All workflows are defined in the [`justfile`](./justfile):

| Command | Action |
|---------|--------|
| `just init` | `terraform init` (providers + modules) |
| `just validate` | validate the configuration |
| `just fmt` | format `.tf` files in place |
| `just plan` / `just apply` | plan / apply changes |
| `just docs` | regenerate README tables via `terraform-docs` |

## Local verification (no AWS account)

`just init`, `just validate`, and `terraform fmt -check -recursive` run fully offline and form the core development loop.

## `plan` / `apply` require live AWS

`just plan` and `just apply` need real AWS credentials **and** a pre-existing VPC, DB subnet group, and security groups (looked up by name). The AWS provider validates credentials via STS **even during `plan`**, so `plan` fails immediately without valid credentials.

## Cursor Cloud agents

Cursor Cloud environment specifics live in the project rule [`.cursor/rules/cloud-agent-environment.mdc`](./.cursor/rules/cloud-agent-environment.mdc).
