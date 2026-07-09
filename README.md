# terraform-aws-rds

Terraform module stack for deploying AWS RDS instances with **zero-downtime upgrade patterns** and **safe rollback capabilities**. Designed for production environments where database migrations need to be safe, repeatable, and recoverable.

## Table of Contents

- [Quickstart](#quickstart)
- [Configuration (Root Module)](#configuration-root-module)
- [When to Use](#when-to-use)
- [Modules Overview](#modules-overview)
- [Detailed Documentation](#detailed-documentation)
- [Contributing](#contributing)

## Quickstart

> [!NOTE]
> This repo uses [`just`](https://github.com/casey/just) as its task runner (`just init`, `just plan`, etc.).
> Install [mise](https://mise.jdx.dev), run **`mise trust`** once to trust [`mise.toml`](./mise.toml), then **`mise install`** from the repo root to install the full toolchain (`terraform`, `just`, `aws`, `terraform-docs`).
> If you already manage tools yourself, you only need `just` (plus whatever each recipe requires).

1. Scaffold local config from an engine example:

```bash
just use-config sqlserver   # or: just use-config mariadb
# edit terraform.tfvars with your VPC, subnets, credentials, etc.
```

2. Run:

```bash
just init
just plan
# review plan
just apply
```

### Minimal Example

```hcl
module "rds_settings" {
  source = "./modules/rds_settings"
  for_each = {
    "v15" = { major_engine_version = "15.00", family = "sqlserver-web-15.0" }
  }
  prefix_name             = "myapp"
  family                  = each.value.family
  engine_name             = "sqlserver-web"
  major_engine_version    = each.value.major_engine_version
}

module "rds_instance" {
  source      = "./modules/rds_instance"
  identifier  = "myapp-dev"
  engine      = module.rds_settings["v15"].engine_name
  engine_version = "15.00.4198.2.v1"
  instance_class = "db.t3.medium"

  parameter_group_name = module.rds_settings["v15"].parameter_group_name
  option_group_name    = module.rds_settings["v15"].option_group_name

  username             = "admin"
  password             = var.db_password
  db_subnet_group_name = var.db_subnet_group_name
  vpc_security_group_ids = var.security_group_ids

  allocated_storage = 100
}
```

### MariaDB (root stack)

Parameter and option groups for MariaDB are defined in `locals.tf` (`v10` for 10.11, `v11` for 11.4). Set `rds_settings_active_key` to select which entry drives the instance — engine and group names come from that key, not a separate engine variable.

Example `.tfvars` for MariaDB 10.11:

```hcl
rds_settings_active_key = "v10"
db_engine_version       = "10.11.10"
db_instance_class       = "db.t3.small"
db_allocated_storage    = 20

license_model          = null
domain                 = null
domain_iam_role_name   = null
```

See [`examples/sqlserver.tfvars.example`](examples/sqlserver.tfvars.example) and [`examples/mariadb.tfvars.example`](examples/mariadb.tfvars.example) for full commented profiles.

## Configuration (Root Module)

Key variables available in the root stack:

| Section | Variable | Description |
|---------|----------|-------------|
| **Networking** | `vpc_id` | VPC ID where resources are deployed |
| **Networking** | `db_subnet_group_name` | Name of the DB subnet group |
| **Networking** | `security_group_names` | List of VPC security group names |
| **Database** | `rds_settings_active_key` | Stable key in `locals.tf` for the running instance (e.g. `v15`, `v10`); drives engine and parameter/option groups |
| **Database** | `db_username` | Master database username |
| **Database** | `db_password` | Master database password |
| **Database** | `db_engine_version` | Target engine version (e.g. full version to pin) |
| **Database** | `db_instance_class` | Instance class (e.g. `db.t3.medium`) |
| **Database** | `db_allocated_storage` | Allocated storage in gigabytes |
| **Storage** | `db_instance_storage_type` | Storage type: gp2 (default), gp3, io1, io2, standard |
| **Storage** | `db_instance_storage_throughput` | Throughput for gp3 (125-1000 MB/s) |
| **Storage** | `db_instance_iops` | Provisioned IOPS for io1/io2 (1000-64000) |
| **Rollback** | `rollback_enabled` | Enable/disable rollback instance |
| **Rollback** | `rollback_snapshot_identifier` | Source snapshot for rollback |

> [!TIP]
> For a full list of variables, see `variables.tf`.

## When to Use

- **Safe Version Upgrades**: Upgrade SQL Server or MariaDB (and other engines) with rollback options
- **Multi-Environment**: Standalone deployments for `dev`, `staging`, or `production`
- **Testing**: Validate new engine versions before committing production users
- **IaC Governance**: Standardized parameter and option group management with version control

## Modules Overview

The stack is distributed across four core modules:

- **[rds_settings](./modules/rds_settings/README.md)**: Manages DB parameter and option groups using stable version keys to prevent accidental recreations.
- **[rds_instance](./modules/rds_instance/README.md)**: Provisioning and management of the RDS DB instances.
- **[rds_networking_data](./modules/rds_networking_data/README.md)**: Optional lookups to fetch existing DB subnets and security groups.
- **[rds_rollback](./modules/rds_rollback/README.md)**: Automated snapshot-based rollback for post-upgrade failures.

## Detailed Documentation

- **[Storage Guide](./docs/storage-guide.md)**: RDS storage types, GP2→GP3 migration, performance tuning, and cost optimization
- **[Rollback Strategy](./docs/rollbacks-snapshot-strategy.md)**: Snapshot-based rollback procedures, best practices, and decision criteria for production.
- **[RDS Parameter & Option Reference](./docs/rds-options-reference.md)**: Comprehensive table of supported engines, parameter group families, and optional configuration blocks.

## Contributing

Contributions are welcome. Please open an issue or submit a Pull Request following the standard repository workflow.

> [!NOTE]
> - **Development guide** — [`AGENTS.md`](./AGENTS.md) (conventions, workflow, command reference)
> - **Toolchain** — [`mise.toml`](./mise.toml) via [mise](https://mise.jdx.dev): `mise install`
> - **Cursor Cloud setup** — [`.cursor/rules/cloud-agent-environment.mdc`](.cursor/rules/cloud-agent-environment.mdc)

## License

MIT
