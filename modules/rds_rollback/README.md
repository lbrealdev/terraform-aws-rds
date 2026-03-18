# RDS Rollback Module

This Terraform module creates an RDS instance from a specific snapshot for rollback scenarios. It wraps the `rds_instance` module and provides a toggle switch to conditionally create a rollback instance.

## Use Case

When a database upgrade fails (e.g., from v15.xx to v16.xx), use this module to:
1. Stop the current (failed) instance
2. Create a new instance from a specific snapshot
3. Maintain the same configuration as the original

## Usage

### Automatic Rollback (Recommended)

```hcl
# Complete rollback with automatic source instance stopping
module "rds_rollback" {
  source = "./modules/rds_rollback"

  enabled             = true
  snapshot_identifier = "rds:mydb-2024-03-18-14-30"  # Specific snapshot
  
  # Automatic stopping of failed instance
  stop_source_instance = true
  source_instance_id   = module.rds_instance_v16.id  # The failed v16 instance
  
  # Same configuration as original instance
  identifier     = "mydb-rollback"
  engine         = "sqlserver-web"
  engine_version = "15.00.4198.2.v1"  # Rollback to original version
  instance_class = "db.t3.medium"
  
  username = "admin"
  password = var.db_password
  
  # Networking (same as original)
  db_subnet_group_name   = module.rds_networking_data.db_subnet_group_name
  vpc_security_group_ids = module.rds_networking_data.security_group_ids
  
  # Settings groups (same as original)
  parameter_group_name = module.rds_settings["v15"].parameter_group_name
  option_group_name    = module.rds_settings["v15"].option_group_name
  
  skip_final_snapshot = true
  apply_immediately   = true
  
  tags = {
    Environment = "production"
    Purpose     = "rollback"
  }
}
```

**What happens:**
1. Creates new instance from snapshot
2. Waits for it to be available
3. Automatically stops the source (failed) instance
4. Ready for DNS/application update

### Integration with Upgrade Flow

```hcl
# STEP 1: Original instance (v15)
module "rds_v15" {
  source = "./modules/rds_instance"
  
  identifier     = "mydb-v15"
  engine         = "sqlserver-web"
  engine_version = "15.00.4198.2.v1"
  # ... other config
}

# STEP 2: Upgrade to v16 (done separately)
module "rds_v16" {
  source = "./modules/rds_instance"
  
  identifier     = "mydb-v16"
  engine         = "sqlserver-web"
  engine_version = "16.00"
  # ... other config
}
# If v16 upgrade fails...

# STEP 3: Rollback to v15 from snapshot
module "rds_rollback" {
  source = "./modules/rds_rollback"
  
  enabled = var.execute_rollback  # Set to true to trigger
  
  # Use snapshot from before upgrade
  snapshot_identifier = "rds:mydb-2024-03-18-14-30"
  
  # Auto-stop the failed v16 instance
  stop_source_instance = true
  source_instance_id   = module.rds_v16.id
  
  # Same config as original v15
  identifier     = "mydb-rollback"
  engine         = "sqlserver-web"
  engine_version = "15.00.4198.2.v1"
  instance_class = "db.t3.medium"
  # ... same other settings
}
```

## How It Works

### Automatic Flow (Recommended)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     AUTOMATIC ROLLBACK FLOW                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. UPGRADE FAILS                                                        │
│     ┌─────────────┐                                                      │
│     │   v16.xx    │  ◄── Failed upgrade instance                        │
│     │   (Failed)  │      Status: issues detected                        │
│     └──────┬──────┘                                                      │
│            │                                                             │
│            │  Trigger: enabled = true                                    │
│            │            snapshot_identifier = "rds:mydb-2024-03-18..."   │
│            │            stop_source_instance = true                      │
│            │            source_instance_id = "mydb-v16"                  │
│            │                                                             │
│            ▼                                                             │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ 2. CREATE ROLLBACK INSTANCE                                     │    │
│  │    rds_rollback module                                          │    │
│  │    ├─ Creates: aws_db_instance from snapshot                    │    │
│  │    ├─ Waits for: status = "available"                           │    │
│  │    └─ Output: endpoint, arn, id                                 │    │
│  │                                                                 │    │
│  │    ┌─────────────┐                                              │    │
│  │    │   v15.xx    │  ◄── NEW instance from snapshot              │    │
│  │    │  (Restored) │      Status: creating → available            │    │
│  │    └──────┬──────┘                                              │    │
│  │           │ (implicit depends_on)                               │    │
│  │           ▼                                                     │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  3. AUTO-STOP SOURCE INSTANCE                                            │
│     ┌──────────────────────────────────────────────────────────┐        │
│     │  aws_rds_instance_state                                  │        │
│     │  ├─ identifier = "mydb-v16"                              │        │
│     │  ├─ state = "stopped"                                    │        │
│     │  └─ Cost: $0 compute, only storage charges               │        │
│     └──────────────────────────────────────────────────────────┘        │
│                                                                          │
│     ┌─────────────┐                                                      │
│     │   v16.xx    │  ◄── STOPPED (preserved for debugging)             │
│     │  (Stopped)  │      Can investigate issues later                  │
│     └─────────────┘                                                      │
│                                                                          │
│  4. UPDATE DNS/APPLICATION                                               │
│     Point to new v15.xx endpoint                                         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Manual Flow (Alternative)

If you prefer manual control, set `stop_source_instance = false` and stop the instance separately.

```hcl
# Option 1: Automatic (recommended)
module "rds_rollback" {
  source = "./modules/rds_rollback"
  
  enabled              = true
  snapshot_identifier  = "rds:mydb-2024-03-18-14-30"
  
  # Automatic stopping
  stop_source_instance = true
  source_instance_id   = module.rds_instance_v16.id
  
  # ... other config
}

# Option 2: Manual control
resource "aws_rds_instance_state" "manual_stop" {
  identifier = module.rds_instance_v16.id
  state      = "stopped"
  
  depends_on = [module.rds_rollback]
}

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.0 |
| aws | >= 5.0 |

## Variables

### Toggle Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `enabled` | Enable or disable the rollback module | `bool` | `false` | No |
| `snapshot_identifier` | The identifier of the DB snapshot to restore from | `string` | `null` | Yes (when enabled) |
| `stop_source_instance` | Automatically stop the source instance after rollback creation | `bool` | `false` | No |
| `source_instance_id` | ID of the source instance to stop (required if stop_source_instance is true) | `string` | `null` | No |

### Instance Configuration (Same as rds_instance)

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `identifier` | The name of the RDS instance | `string` | - | Yes |
| `engine` | The database engine | `string` | - | Yes |
| `engine_version` | The engine version | `string` | - | Yes |
| `instance_class` | The instance type | `string` | - | Yes |
| `username` | Username for master DB user | `string` | `null` | Yes |
| `password` | Password for master DB user | `string` | `null` | Yes |
| `allocated_storage` | Allocated storage in GB | `number` | `20` | No |
| `storage_type` | Storage type | `string` | `"gp2"` | No |
| `db_subnet_group_name` | Name of DB subnet group | `string` | `null` | No |
| `vpc_security_group_ids` | List of VPC security groups | `list(string)` | `[]` | No |
| `parameter_group_name` | Name of DB parameter group | `string` | `null` | No |
| `option_group_name` | Name of DB option group | `string` | `null` | No |
| `skip_final_snapshot` | Skip final snapshot | `bool` | `true` | No |
| `apply_immediately` | Apply changes immediately | `bool` | `null` | No |
| `allow_major_version_upgrade` | Allow major version upgrades | `bool` | `null` | No |
| `auto_minor_version_upgrade` | Auto minor version upgrades | `bool` | `null` | No |
| `tags` | Map of tags | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| `endpoint` | The connection endpoint (hostname:port) |
| `address` | The hostname |
| `port` | The database port |
| `arn` | The RDS instance ARN |
| `id` | The RDS instance ID |
| `resource_id` | The RDS Resource ID |
| `status` | The RDS instance status |
| `availability_zone` | The availability zone |
| `engine` | The database engine |
| `engine_version` | The running engine version |

All outputs return `null` when `enabled = false`.

## Important Notes

- **New Instance**: The rollback creates a NEW instance, not restore to the original
- **Different Endpoint**: The restored instance has a different endpoint/ARN
- **Data Loss**: Any data changes after the snapshot timestamp are lost
- **Automatic Stopping**: Set `stop_source_instance = true` to auto-stop the failed instance after rollback is ready
- **DNS Update**: Remember to update Route 53 or application connection strings
- **Cost**: Stopped instances incur only storage charges (no compute costs)
- **Preservation**: Failed instance is preserved for debugging, not deleted

## Rollback Checklist

Before executing rollback:

- [ ] Identify the specific snapshot to restore from
- [ ] Set `stop_source_instance = true` for automatic stopping (or plan manual stop)
- [ ] Note the source instance ID (`source_instance_id`)
- [ ] Note the original instance configuration
- [ ] Prepare to update DNS/application connection strings
- [ ] Notify team of rollback in progress
- [ ] Verify snapshot exists and is available

After rollback:

- [ ] Verify restored instance is available
- [ ] Confirm source instance is stopped (check AWS Console)
- [ ] Test connectivity to new endpoint
- [ ] Update DNS records to point to new instance
- [ ] Verify application functionality
- [ ] Document rollback reason and resolution
- [ ] Plan investigation of upgrade failure
- [ ] Decide when to delete the stopped failed instance

## Differences from rds_instance Module

| Feature | rds_instance | rds_rollback |
|---------|--------------|--------------|
| Purpose | Create new DB | Create from snapshot |
| Toggle | N/A | `enabled` variable |
| Snapshot | No | `snapshot_identifier` |
| Auto-stop source | N/A | `stop_source_instance` + `source_instance_id` |
| Use case | Initial deployment | Recovery from failed upgrade |

## License

MIT
