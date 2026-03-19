# RDS Settings Module

This Terraform module creates RDS Option Groups and Parameter Groups for different SQL Server versions.

## Usage

### Creating a Single RDS Instance (Option 2)

To create a single RDS instance using a specific version (e.g., SQL Server 2022 / v16):

```hcl
module "rds_instance" {
  source = "./modules/rds_instance"
  
  # Reference specific version from rds_settings
  parameter_group_name = module.rds_settings["v16"].parameter_group_name
  option_group_name    = module.rds_settings["v16"].option_group_name
  
  # RDS Instance Configuration
  identifier = "${local.prefix_name}-v16"  # Results in: dev-v16
  
  # Required db_instance arguments
  engine         = "sqlserver-web"
  engine_version = "16.00"
  instance_class = "db.t3.micro"
  allocated_storage = 20
  
  # Other configuration
  db_name  = "mydatabase"
  username = "admin"
  password = var.db_password
  
  # ... other db_instance settings
}
```

### Available Versions

The module currently supports:
- `v15` - SQL Server 2019 (15.00)
- `v16` - SQL Server 2022 (16.00)

To use a different version, reference it by key:
- `module.rds_settings["v15"]` for SQL Server 2019
- `module.rds_settings["v16"]` for SQL Server 2022

### Module Outputs

The `rds_settings` module provides these outputs:

```hcl
# Parameter group resources
module.rds_settings["v16"].parameter_group_name  # "dev-parameter-group-16"
module.rds_settings["v16"].parameter_group_arn   # ARN for IAM policies

# Option group resources
module.rds_settings["v16"].option_group_name     # "dev-option-group-16"
module.rds_settings["v16"].option_group_id       # ID for references
```

### Root Module Outputs

When applied, these outputs are available:

```hcl
rds_parameter_group_names = {
  "v15" = "dev-parameter-group-15"
  "v16" = "dev-parameter-group-16"
}

rds_option_group_names = {
  "v15" = "dev-option-group-15"
  "v16" = "dev-option-group-16"
}
```

### Adding/Removing Versions

To add or remove SQL Server versions, edit `locals.tf`:

```hcl
locals {
  rds_settings = {
    "v15" = { ... }  # Remove this line to delete v15
    "v16" = { ... }  # Keep this for v16
    # Add new versions here with a unique key
  }
}
```

**Important:** Using `for_each` with stable keys (v15, v16) ensures that adding/removing versions doesn't recreate existing resources.

### Resource Naming Convention

Resources are named using the pattern:
- Parameter Group: `{prefix}-parameter-group-{major_version}`
  - Example: `dev-parameter-group-16`
- Option Group: `{prefix}-option-group-{major_version}`
  - Example: `dev-option-group-16`

The `major_engine_version` (e.g., "16.00") is cleaned to extract just the integer ("16") for naming.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Variables

### rds_settings Module

| Name | Description | Type | Required |
|------|-------------|------|----------|
| `prefix` | Prefix for resource names | `string` | Yes |
| `family` | Parameter group family (e.g., `sqlserver-web-15.0`) | `string` | Yes |
| `engine_name` | Database engine name (e.g., `sqlserver-web`) | `string` | Yes |
| `major_engine_version` | Major engine version (e.g., `15.00`) | `string` | Yes |
| `option_group_description` | Description for option group | `string` | No |
| `parameter_group_description` | Description for parameter group | `string` | No |
| `parameter_group_parameters` | List of parameter objects | `list(object)` | No |
| `option_group_options` | List of option objects | `list(object)` | No |

### Parameter Object Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `name` | Yes | Parameter name |
| `value` | Yes | Parameter value |
| `apply_method` | No | `immediate` (default) or `pending-reboot` |

### Option Object Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `option_name` | Yes | Option name |
| `db_security_group_memberships` | No | List of DB security group names |
| `option_settings` | No | List of `{name, value}` objects |
| `port` | No | Port number |
| `version` | No | Option version |
| `vpc_security_group_memberships` | No | List of VPC security group IDs |

## License

MIT
