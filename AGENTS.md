# terraform-aws-rds — Development Guide

## Project

Reusable Terraform module stack for provisioning AWS RDS instances (SQL Server,
MySQL, MariaDB, PostgreSQL/Aurora) with an emphasis on safe engine upgrades and recovery:

- **Version-stable settings** — parameter/option groups keyed by engine version
  (`v15`/`v16`/`v17` for SQL Server; `v10`/`v11` for MariaDB) so upgrades don't force resource recreation
- **Snapshot-based rollback** — restore from a snapshot and stop the source
  instance for post-upgrade recovery

Root stack plus four modules: `rds_settings`, `rds_instance`,
`rds_networking_data`, `rds_rollback`.

## Workflow

Issue → Branch → Implement → PR → Review → Merge to main

## Conventions

### Branches & commits

| Prefix | Branch | Commit |
|--------|--------|--------|
| `feat` | `feat/gp3-storage` | `feat(storage): add gp3 support` |
| `fix` | `fix/subnet-lookup` | `fix: handle missing subnet group` |
| `docs` | `docs/rollback-guide` | `docs: document rollback strategy` |
| `refactor` | `refactor/settings` | `refactor: simplify option groups` |
| `chore` | — | `chore: bump provider version` |

### Rules

- Never commit to `main`
- Never force-push
- Never commit secrets, `*.tfvars`, or state files (`*.tfstate`)
- Use `git` for version control, `gh` for GitHub operations

### Code style

- Terraform `>= 1.0`, AWS provider `>= 6.0`
- Run `just fmt` before committing
- Keep version setting keys stable (`v15`/`v16`/`v17` for SQL Server; `v10`/`v11` for MariaDB) to avoid resource recreation
- Networking is looked up, not created — assume VPC/subnet group/SGs pre-exist
- Follow the patterns in the module you're editing

## Commands

```bash
mise trust         # trust mise.toml (once per machine)
mise install       # install the toolchain (mise.toml)
just init          # terraform init (providers + modules)
just validate      # validate configuration
just fmt           # format .tf files
just plan          # plan (needs AWS creds + existing network)
just apply         # apply
```

## Cloud agent environments

Automated environments install the toolchain via `mise` (`mise.toml`). `plan`
and `apply` need real AWS credentials plus a pre-existing VPC, DB subnet group,
and security groups — the provider validates credentials via STS even during
`plan` — so agents can only run the offline loop (`just init`, `just validate`,
`just fmt`) without AWS access.

Per-platform setup lives with its own config; Cursor Cloud is in
[`.cursor/rules/cloud-agent-environment.mdc`](.cursor/rules/cloud-agent-environment.mdc).
