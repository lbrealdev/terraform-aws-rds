# RDS Networking Data Module

This Terraform module fetches existing AWS RDS networking resources (DB subnet groups and security groups) using data sources. It provides a toggle switch to conditionally enable or disable lookups.

## Usage

### Basic Usage

```hcl
module "rds_networking" {
  source = "./modules/rds_networking_data"

  enabled              = true
  db_subnet_group_name = "my-existing-db-subnet-group"
  
  vpc_id               = "vpc-12345678"
  security_group_names = ["rds-security-group", "app-security-group"]
}
```

### Conditional Usage with RDS Instance

```hcl
module "rds_networking" {
  source = "./modules/rds_networking_data"

  enabled              = var.use_existing_networking
  db_subnet_group_name = var.existing_db_subnet_group_name
  vpc_id               = var.vpc_id
  security_group_names = var.existing_security_group_names
}

module "rds_instance" {
  source = "./modules/rds_instance"

  identifier             = "my-db-instance"
  engine                 = "sqlserver-web"
  engine_version         = "16.00"
  instance_class         = "db.t3.micro"
  username               = "admin"
  password               = var.db_password
  
  # Use fetched networking resources
  db_subnet_group_name   = var.use_existing_networking ? module.rds_networking.db_subnet_group_name : aws_db_subnet_group.new[0].name
  vpc_security_group_ids = var.use_existing_networking ? module.rds_networking.security_group_ids : [aws_security_group.new.id]
  
  skip_final_snapshot    = true
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `enabled` | Enable or disable the data lookups | `bool` | `true` | No |
| `db_subnet_group_name` | Name of the existing DB subnet group to fetch | `string` | `null` | No |
| `security_group_names` | List of existing security group names to fetch | `list(string)` | `[]` | No |
| `vpc_id` | VPC ID where security groups are located | `string` | `null` | No |

## Outputs

| Name | Description |
|------|-------------|
| `db_subnet_group_name` | Name of the fetched DB subnet group |
| `db_subnet_group_arn` | ARN of the fetched DB subnet group |
| `db_subnet_group_description` | Description of the fetched DB subnet group |
| `db_subnet_group_subnets` | List of subnet IDs in the DB subnet group |
| `security_group_ids` | List of IDs of the fetched security groups |
| `security_group_names` | List of names of the fetched security groups |
| `security_groups_by_name` | Map of security group names to their IDs |
| `enabled` | Whether the module is enabled |

## Notes

- When `enabled` is set to `false`, all outputs will return empty values or `null`
- The module uses `count` and `for_each` with conditions to avoid errors when lookups are disabled
- At least one of `db_subnet_group_name` or `security_group_names` should be provided when enabled
- `vpc_id` is required when fetching security groups by name to ensure uniqueness

## License

MIT
