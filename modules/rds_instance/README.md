# RDS Instance Module

This Terraform module creates an AWS RDS DB instance with configurable settings.

## Usage

### Basic Usage

```hcl
module "rds_instance" {
  source = "./modules/rds_instance"

  # Required configuration
  enabled       = true
  identifier     = "my-app-db"
  engine         = "sqlserver-web"
  engine_version = "16.00"
  instance_class = "db.t3.micro"
  username       = "admin"
  password       = var.db_password

  # Networking
  db_subnet_group_name   = "my-db-subnet-group"
  vpc_security_group_ids = ["sg-12345678"]

  # Storage (default gp2)
  allocated_storage = 20
  storage_type      = "gp2"
}
```

### GP3 Storage Configuration (Recommended)

GP3 provides better price-performance ratio with tunable IOPS and throughput.

```hcl
module "rds_instance" {
  source = "./modules/rds_instance"

  enabled       = true
  identifier     = "my-app-db"
  engine         = "sqlserver-web"
  engine_version = "16.00"
  instance_class = "db.t3.micro"
  username       = "admin"
  password       = var.db_password

  # Networking
  db_subnet_group_name   = "my-db-subnet-group"
  vpc_security_group_ids = ["sg-12345678"]

  # Storage (gp3 with tunable performance)
  allocated_storage     = 100
  storage_type          = "gp3"
  storage_throughput    = 300  # 125-1000 MB/s
  iops                  = 3000 # 3000-16000 (optional, uses baseline if null)
}
```

### IO1 High-Performance Storage

For IOPS-intensive workloads requiring consistent low latency.

```hcl
module "rds_instance" {
  source = "./modules/rds_instance"

  enabled       = true
  identifier     = "my-app-db"
  engine         = "sqlserver-web"
  engine_version = "16.00"
  instance_class = "db.t3.medium"
  username       = "admin"
  password       = var.db_password

  # Networking
  db_subnet_group_name   = "my-db-subnet-group"
  vpc_security_group_ids = ["sg-12345678"]

  # Storage (io1 for high IOPS workloads)
  allocated_storage = 200
  storage_type      = "io1"
  iops              = 5000 # 1000-64000
}
```

> [!TIP]
> See [Storage Guide](../../docs/storage-guide.md) for detailed comparison, migration strategies, and cost optimization.

### Usage with RDS Settings Module

```hcl
module "rds_settings" {
  source   = "./modules/rds_settings"
  for_each = local.rds_settings

  prefix                      = var.prefix_name
  family                      = each.value.parameter_group.family
  parameter_group_description = try(each.value.parameter_group.description, null)
  parameter_group_parameters  = try(each.value.parameter_group.parameters, [])

  engine_name              = each.value.option_group.engine_name
  major_engine_version     = each.value.option_group.major_engine_version
  option_group_description = each.value.option_group.description
  option_group_options     = try(each.value.option_group.options, [])
}

module "rds_instance" {
  source = "./modules/rds_instance"

  enabled = true

  # Reference specific version from rds_settings
  parameter_group_name = module.rds_settings["v16"].parameter_group_name
  option_group_name    = module.rds_settings["v16"].option_group_name

  # RDS Instance Configuration
  identifier     = "${var.prefix_name}-v16"
  engine         = module.rds_settings["v16"].engine_name
  engine_version = "16.00"
  instance_class = "db.t3.micro"

  username = "admin"
  password = var.db_password

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Storage
  allocated_storage = 100
  storage_type      = "gp3" # Recommended: better price-performance ratio

  # Optional GP3 tuning (see docs/storage-guide.md)
  storage_throughput = 300  # 125-1000 MB/s
  iops               = 3000 # 3000-16000 (optional)

  # Maintenance settings
  skip_final_snapshot = true
  apply_immediately   = false

  tags = {
    Environment = "production"
    Project     = "myapp"
  }
}
```

### MariaDB with RDS Settings Module

```hcl
module "rds_instance" {
  source = "./modules/rds_instance"

  enabled = true

  parameter_group_name = module.rds_settings["v10"].parameter_group_name
  option_group_name    = module.rds_settings["v10"].option_group_name

  identifier     = "${var.prefix_name}-mariadb"
  engine         = module.rds_settings["v10"].engine_name
  engine_version = "10.11.10"
  instance_class = "db.t3.small"

  username = "admin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  allocated_storage = 20
  storage_type      = "gp3"
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.2 |
| aws | >= 5.0 |

## Variables

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| `enabled` | Enable or disable the RDS instance creation | `bool` |
| `identifier` | The name of the RDS instance | `string` |
| `engine` | The database engine to use (e.g., mariadb, mysql, postgres, sqlserver-web) | `string` |
| `engine_version` | The engine version to use | `string` |
| `instance_class` | The instance type of the RDS instance | `string` |
| `username` | Username for the master DB user | `string` |
| `password` | Password for the master DB user | `string` |
| `db_subnet_group_name` | Name of DB subnet group | `string` |

### Optional Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `allocated_storage` | The allocated storage in gigabytes | `number` | `100` |
| `storage_type` | Storage type: standard, gp2 (default), gp3, io1, io2 | `string` | `"gp2"` |
| `storage_throughput` | Throughput for gp3 (125-1000 MB/s) | `number` | `null` |
| `iops` | Provisioned IOPS for io1/io2 (1000-64000) | `number` | `null` |
| `skip_final_snapshot` | Skip final snapshot before deletion | `bool` | `true` |
| `vpc_security_group_ids` | List of VPC security groups to associate | `list(string)` | `[]` |
| `option_group_name` | Name of the DB option group to associate | `string` | `null` |
| `parameter_group_name` | Name of the DB parameter group to associate | `string` | `null` |
| `allow_major_version_upgrade` | Allow major version upgrades | `bool` | `null` |
| `auto_minor_version_upgrade` | Apply minor upgrades automatically | `bool` | `null` |
| `apply_immediately` | Apply changes immediately or during maintenance window | `bool` | `null` |
| `multi_az` | Specifies if the RDS instance is multi-AZ | `bool` | `false` |
| `tags` | A map of tags to add to all resources | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `endpoint` | The connection endpoint for the RDS instance (hostname:port) |
| `address` | The hostname of the RDS instance |
| `port` | The port on which the database accepts connections |
| `arn` | The ARN of the RDS instance |
| `id` | The RDS instance ID |
| `resource_id` | The RDS Resource ID |
| `status` | The RDS instance status |
| `availability_zone` | The availability zone of the RDS instance |
| `engine` | The database engine |
| `engine_version` | The running version of the database |

## Notes

- **Enabled Toggle:** Set `enabled = false` to create the module without deploying an actual RDS instance. This is useful for testing `rds_settings` module without provisioning database resources.
- **Security:** The `password` variable is marked as sensitive to prevent it from appearing in logs and CLI output.
- **Final Snapshots:** By default, `skip_final_snapshot` is set to `true` for easier deletion during development. Set to `false` for production to prevent data loss.
- **Apply Immediately:** Changes are deferred to the maintenance window by default. Set `apply_immediately = true` for immediate changes (may cause brief downtime).
- **Version Upgrades:** Use `allow_major_version_upgrade` and `auto_minor_version_upgrade` to control upgrade behavior.
- **Engine Versions:** You can specify either partial versions (e.g., `"15.00"`) for automatic latest patch selection, or full versions (e.g., `"15.00.4198.2.v1"`) for immutable deployments. See the main README for detailed version management guidance.
- **SQL Server–only variables:** `license_model`, `domain`, and `domain_iam_role_name` apply to SQL Server only. Leave them unset or `null` for MariaDB and other engines.
- **Instance class floors:** Invalid SQL Server Enterprise/Standard + undersized `instance_class` combinations (e.g. `sqlserver-ee` + `db.t3.medium`) fail at plan via a resource precondition.
- **Multi-AZ:** Set `multi_az = true` for a standby replica in another Availability Zone. The DB subnet group must span at least two AZs.

## References

- [Terraform `aws_db_instance`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance)

## License

MIT
