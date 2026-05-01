# terraform-aws-rds

A complete Terraform module stack for deploying AWS RDS instances that supports **zero-downtime upgrades** and **rollback capabilities**. This repository provides a modular approach to RDS management with version-controlled parameter and option groups.

## Overview

This RDS stack is designed for production environments where:
- **Database upgrades** need to be performed safely with rollback options
- **Multiple SQL Server versions** need to coexist or migrate between
- **Infrastructure as Code** requires consistent, repeatable deployments
- **Blue/Green deployments** or parallel version testing is needed

## Architecture

The stack consists of four complementary modules:

### [RDS Settings Module](./modules/rds_settings/README.md)
Manages RDS configuration groups across multiple database versions using `for_each` for stable resource management.

- **Parameter Groups**: Database engine configuration
- **Option Groups**: Database features and extensions
- **Version Management**: Support for multiple concurrent SQL Server versions
- **Stable Keys**: Uses version keys (v15, v16) to prevent accidental recreation

### [RDS Instance Module](./modules/rds_instance/README.md)
Creates the actual RDS database instances with configurable settings.

- **Flexible Configuration**: Support for various instance types and engines
- **Network Integration**: VPC security groups and subnet groups
- **Maintenance Controls**: Version upgrades, snapshots, and immediate apply settings
- **Complete Outputs**: Endpoint, ARN, status, and connection details

### [RDS Networking Data Module](./modules/rds_networking_data/README.md)
Fetches existing AWS networking resources with a toggle switch for conditional lookups.

- **Existing Resource Lookup**: Fetch existing DB subnet groups and security groups
- **Conditional Enable/Disable**: Toggle switch to control data source execution
- **Flexible Networking**: Use existing or create new networking resources
- **Zero-Cost Operation**: Data sources are free to query

### [RDS Rollback Module](./modules/rds_rollback/README.md)
Creates RDS instances from snapshots for rollback scenarios after failed upgrades.

- **Snapshot-Based Recovery**: Restore from specific point-in-time snapshots
- **Same Configuration**: Uses same interface as rds_instance module
- **Toggle Control**: Enable/disable rollback instance creation
- **Safe Rollback**: Creates new instance while preserving failed one for analysis

## Quick Start

### Deploy Multiple SQL Server Versions

```hcl
module "rds_settings" {
  source   = "./modules/rds_settings"
  for_each = {
    "v15" = { major_engine_version = "15.00", family = "sqlserver-web-15.0" }
    "v16" = { major_engine_version = "16.00", family = "sqlserver-web-16.0" }
  }

  prefix_name             = "production"
  family                  = each.value.family
  engine_name             = "sqlserver-web"
  major_engine_version    = each.value.major_engine_version
}

module "rds_instance_v16" {
  source = "./modules/rds_instance"

  identifier     = "production-app-v16"
  engine         = "sqlserver-web"
  engine_version = "16.00"
  instance_class = "db.t3.micro"

  parameter_group_name = module.rds_settings["v16"].parameter_group_name
  option_group_name    = module.rds_settings["v16"].option_group_name

  username             = "admin"
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  skip_final_snapshot = false
  apply_immediately   = false
}
```

## Configuring Parameters and Options

The `locals.tf` file defines shared `rds_parameters` and `rds_options` variables that are applied to all SQL Server versions. This allows you to define parameters and options once and reuse them across version configurations.

### Example: Database Parameters

```hcl
# In locals.tf
locals {
  rds_parameters = [
    {
      name         = "max_connections"
      value        = "100"
      apply_method = "immediate"
    },
    {
      name         = "locked"
      value        = "1"
      apply_method = "pending-reboot"
    }
  ]

  rds_options = [
    {
      option_name = "SQLSERVER_BACKUP_RESTORE"
      option_settings = [
        {
          name  = "IAM_ROLE_ARN"
          value = "arn:aws:iam::123456789:role/my-backup-role"
        }
      ]
    }
  ]

  rds_settings = {
    # ... version configurations reference local.rds_parameters and local.rds_options
  }
}
```

### Parameter Block Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `name` | Yes | Parameter name (e.g., `max_connections`) |
| `value` | Yes | Parameter value |
| `apply_method` | No | `immediate` (default) or `pending-reboot` |

### Option Block Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `option_name` | Yes | Option name (e.g., `SQLSERVER_BACKUP_RESTORE`) |
| `db_security_group_memberships` | No | List of DB security group names |
| `option_settings` | No | List of setting objects with `name` and `value` |
| `port` | No | Port number for the option |
| `version` | No | Option version |
| `vpc_security_group_memberships` | No | List of VPC security group IDs |

### Common Options for SQL Server

**SQLSERVER_BACKUP_RESTORE** - Enable native backup/restore with S3:
```hcl
rds_options = [
  {
    option_name = "SQLSERVER_BACKUP_RESTORE"
    option_settings = [
      {
        name  = "IAM_ROLE_ARN"
        value = "arn:aws:iam::123456789:role/my-backup-role"
      }
    ]
  }
]
```

**SQLSERVER Native BACKUP** - Configure backup schedule:
```hcl
rds_options = [
  {
    option_name = "SQLSERVER_BACKUP"
    option_settings = [
      {
        name  = "BACKUP_HOUR"
        value = "02"  # 2 AM UTC
      },
      {
        name  = "BACKUP_MINUTE"
        value = "00"
      },
      {
        name  = "ENABLED"
        value = "true"
      }
    ]
  }
]
```

## Repository Structure

```
terraform-aws-rds/
├── modules/
│   ├── rds_instance/           # RDS instance creation
│   │   ├── README.md
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── rds_settings/           # Parameter & option groups management
│   │   ├── README.md
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── locals.tf
│   │   └── outputs.tf
│   ├── rds_networking_data/    # Fetch existing networking resources
│   │   ├── README.md
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── rds_rollback/           # Create instances from snapshots
│       ├── README.md
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── README.md                   # This file
├── variables.tf                # Root module variables
├── terraform.tfvars            # Variable values (environment-specific)
├── terraform.tfvars.example    # Variable template
└── .gitignore
```

## Configuration Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    TERRAFORM CONFIGURATION FLOW                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. VARIABLES DEFINITION (variables.tf)                                  │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Define all configurable parameters with:                        │   │
│  │  • Type constraints (string, bool, list, etc.)                   │   │
│  │  • Descriptions                                                  │   │
│  │  • Default values (optional)                                     │   │
│  │                                                                  │   │
│  │  Example:                                                        │   │
│  │  variable "db_instance_class" {                                  │   │
│  │    type    = string                                              │   │
│  │    default = "db.t3.medium"                                      │   │
│  │  }                                                               │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                              │                                           │
│                              ▼                                           │
│  2. VARIABLE VALUES (terraform.tfvars)                                   │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Override defaults with environment-specific values:             │   │
│  │                                                                  │   │
│  │  db_instance_class = "db.t3.large"                             │   │
│  │  db_username       = "admin"                                   │   │
│  │  aws_region        = "eu-central-1"                            │   │
│  │                                                                  │   │
│  │  ⚠️  NEVER commit secrets:                                     │   │
│  │  • Add terraform.tfvars to .gitignore                          │   │
│  │  • Use environment variables for sensitive data                │   │
│  │  • Or use AWS Secrets Manager / Parameter Store                │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                              │                                           │
│                              ▼                                           │
│  3. USAGE IN MAIN.TF                                                     │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Reference variables in resources/modules:                       │   │
│  │                                                                  │   │
│  │  module "rds_instance" {                                         │   │
│  │    source        = "./modules/rds_instance"                      │   │
│  │    instance_class = var.db_instance_class                        │   │
│  │    username      = var.db_username                               │   │
│  │  }                                                               │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                              │                                           │
│                              ▼                                           │
│  4. DEPLOYMENT                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  # Use values from terraform.tfvars                              │   │
│  │  terraform apply                                                 │   │
│  │                                                                  │   │
│  │  # Override specific values                                      │   │
│  │  terraform apply -var="db_instance_class=db.r5.xlarge"         │   │
│  │                                                                  │   │
│  │  # Use different environment file                                │   │
│  │  terraform apply -var-file="prod.tfvars"                       │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  VARIABLE PRECEDENCE (highest to lowest):                                │
│  1. CLI flags: -var or -var-file                                         │
│  2. *.auto.tfvars files                                                  │
│  3. terraform.tfvars                                                     │
│  4. Environment variables: TF_VAR_name                                   │
│  5. Default values in variables.tf                                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Modules

| Module | Description | Documentation |
|--------|-------------|---------------|
| **rds_instance** | Creates RDS DB instances with full configuration | [View Docs](./modules/rds_instance/README.md) |
| **rds_settings** | Manages parameter and option groups for upgrades | [View Docs](./modules/rds_settings/README.md) |
| **rds_networking_data** | Fetches existing subnet groups and security groups | [View Docs](./modules/rds_networking_data/README.md) |
| **rds_rollback** | Creates instances from snapshots for rollback | [View Docs](./modules/rds_rollback/README.md) |

## Engine Version Management

Understanding RDS engine versioning is crucial for predictable deployments:

### Partial vs. Full Version Strings

RDS accepts two formats for engine versions:

**Partial Version (e.g., "15.00"):**
- AWS automatically selects the latest available patch version
- Example: `15.00` → `15.00.4455.2.v1` (latest at deployment time)
- **Risk**: Your database may upgrade to a newer patch version unexpectedly on redeployment

**Full Version (e.g., "15.00.4198.2.v1"):**
- Pin to an exact, specific version
- Example: `15.00.4198.2.v1` stays locked to that patch
- **Benefit**: Immutable, repeatable deployments with no surprise updates

### Best Practices

1. **Pin Full Versions for Production**
   ```hcl
   rds_engine_version = "15.00.4198.2.v1"  # Exact, immutable
   ```

2. **Use Partial Versions for Development**
   ```hcl
   rds_engine_version = "15.00"  # Always latest patch
   ```

3. **Check Available Versions**
   ```bash
   aws rds describe-db-engine-versions \
     --engine sqlserver-web \
     --query 'DBEngineVersions[].EngineVersion'
   ```

This approach ensures your infrastructure remains stable and predictable across deployments.

## Upgrade & Rollback Strategy

### Safe Upgrade Process

1. **Deploy New Version in Parallel**
   ```hcl
   # Add new version to rds_settings
   for_each = {
     "v15" = { ... }  # Existing
     "v16" = { ... }  # New version
   }
   ```

2. **Create New RDS Instance**
   - Deploy new instance with new version
   - Test applications against new instance
   - Migrate data using AWS DMS or backup/restore

3. **Switch Applications**
   - Update application connection strings
   - Use Route 53 or ALB for seamless switching

4. **Remove Old Version**
   ```hcl
   # Remove old version when migration complete
   for_each = {
     "v16" = { ... }  # Keep only new version
   }
   ```

### Rollback Capability

- **Keep old versions** in `rds_settings` during migration
- **Retain snapshots** by setting `skip_final_snapshot = false`
- **Parallel instances** allow quick DNS switchback
- **Stable keys** prevent accidental recreation of existing resources

### Snapshot Rollback Strategy

For detailed rollback procedures using the `rds_rollback` module, see [ROLLBACK_STRATEGY.md](./ROLLBACK_STRATEGY.md).

This covers:
- Automated backup integration (daily/monthly snapshots)
- Step-by-step rollback procedures
- When to use snapshot vs Blue/Green strategies
- Cost and downtime considerations

## Requirements

- Terraform >= 1.0
- AWS Provider >= 5.0
- AWS Account with RDS permissions

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Submit a pull request

## License

MIT
