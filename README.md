# terraform-aws-rds

Terraform module stack for deploying AWS RDS with support for **zero-downtime upgrades** patterns and **rollback capabilities**.

## Modules

- **rds_settings**: DB parameter groups + option groups (stable naming across engine versions)
- **rds_instance**: creates the RDS DB instance
- **rds_networking_data**: optionally looks up existing DB subnet group + security groups
- **rds_rollback**: creates an instance from a snapshot for rollback scenarios

## Quickstart

> Adjust variables and examples below to your engine/version.

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

## Upgrade & rollback docs

See the detailed guides in `docs/`:
- [Rollback strategy (snapshot-based)](./docs/rollbacks-snapshot-strategy.md)
- [RDS parameter/option reference](./docs/rds-options-reference.md)

## Documentation structure

- Root `README.md`: entry point / overview
- `docs/`: detailed guides, references, and examples
- `modules/*/README.md`: module-specific behavior and outputs

## Contributing

Contributions are welcome via Pull Requests.

## License

MIT
