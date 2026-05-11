# terraform-aws-rds

Terraform module stack for deploying AWS RDS with support for **zero-downtime upgrade patterns** and **rollback capabilities**.

> **Quick navigation**
> - [Quickstart](#quickstart)
> - [Configuration (root module)](#configuration-root-module)
> - [Modules](#modules)
> - [Upgrade & rollback](#upgrade--rollback)
> - [References](#references)
> - [Contributing](#contributing)

## Quickstart

1) Configure required variables (see `variables.tf`)
2) Run:

```bash
just init
just plan
# review plan
just apply
```

## Configuration (root module)

Key variables:
- `aws_region`
- `prefix_name`
- `vpc_id`
- `db_subnet_group_name`
- `security_group_names`
- `db_username` / `db_password`
- `rds_engine_version`, `db_instance_class`, `db_allocated_storage`

Rollback controls:
- `rollback_enabled`
- `rollback_snapshot_identifier`
- `rollback_identifier`

## Modules

- **rds_settings**: DB parameter groups + option groups (stable naming across engine versions)
- **rds_instance**: creates the RDS DB instance
- **rds_networking_data**: optionally looks up existing DB subnet group + security groups
- **rds_rollback**: creates an instance from a snapshot for rollback scenarios

## Upgrade & rollback

Detailed guides live in `docs/`:
- [Rollback strategy (snapshot-based)](./docs/rollbacks-snapshot-strategy.md)
- [RDS parameter/option reference](./docs/rds-options-reference.md)

## References

- Module READMEs (more operational details):
  - `modules/rds_settings/README.md`
  - `modules/rds_instance/README.md`
  - `modules/rds_networking_data/README.md`
  - `modules/rds_rollback/README.md`

## Contributing

Contributions are welcome via Pull Requests.

## License

MIT
