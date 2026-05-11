# terraform-aws-rds

Terraform module stack for deploying AWS RDS instances with **zero-downtime upgrade patterns** and **safe rollback capabilities**. Designed for production environments where database migrations need to be safe, repeatable, and recoverable.

> [!NOTE]
> The RDS modules support **SQL Server**, **MySQL**, and **PostgreSQL** (including Aurora).

## Table of Contents

- [Quickstart](#quickstart)
- [Configuration (Root Module)](#configuration-root-module)
- [When to Use](#when-to-use)
- [Modules Overview](#modules-overview)
- [Detailed Documentation](#detailed-documentation)
- [Contributing](#contributing)

## Quickstart

1. Configure required variables (see `variables.tf`)
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

## Configuration (Root Module)

Key variables available in the root stack:

| Section | Variable | Description |
|---------|----------|-------------|
| **Networking** | `vpc_id` | VPC ID where resources are deployed |
| **Networking** | `db_subnet_group_name` | Name of the DB subnet group |
| **Networking** | `security_group_names` | List of VPC security group names |
| **Database** | `db_username` | Master database username |
| **Database** | `db_password` | Master database password |
| **Database** | `rds_engine_version` | Target engine version (e.g. full version to pin) |
| **Database** | `db_instance_class` | Instance class (e.g. `db.t3.medium`) |
| **Database** | `db_allocated_storage` | Allocated storage in gigabytes |
| **Rollback** | `rollback_enabled` | Enable/disable rollback instance |
| **Rollback** | `rollback_snapshot_identifier` | Source snapshot for rollback |

> [!TIP]
> For a full list of variables, see `variables.tf`.

## When to Use

- **Safe Version Upgrades**: Upgrade SQL Server / MySQL / PostgreSQL with rollback options
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

- **[Rollback Strategy](./docs/rollbacks-snapshot-strategy.md)**: Snapshot-based rollback procedures, best practices, and decision criteria for production.
- **[RDS Parameter & Option Reference](./docs/rds-options-reference.md)**: Comprehensive table of supported engines, parameter group families, and optional configuration blocks.

## Contributing

Contributions are welcome. Please open an issue or submit a Pull Request following the standard repository workflow.

## License

MIT
