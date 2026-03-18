# RDS Snapshot Rollback Strategy

This document describes the snapshot-based rollback approach for RDS major version upgrades.

## Overview

The snapshot rollback strategy provides a simple, cost-effective way to revert to a previous database version when upgrade issues occur. This approach trades zero-downtime capability for simplicity and cost savings.

## Architecture Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SNAPSHOT ROLLBACK FLOW                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  BEFORE UPGRADE                                                          │
│  ┌─────────────┐        Create           ┌─────────────┐                │
│  │   v15.xx    │ ───────────────────────►│   Snapshot  │                │
│  │  (Active)   │        (Automated       │  (Daily/    │                │
│  └─────────────┘         Backup)         │   Monthly)  │                │
│                                          └──────┬──────┘                │
│                                                 │                        │
│  UPGRADE                                        ▼                        │
│  ┌─────────────┐        Modify           ┌─────────────┐                │
│  │   v15.xx    │ ───────────────────────►│   v16.xx    │                │
│  │  (Snapshot) │     15.00 → 16.00       │   (Issues)  │                │
│  └─────────────┘                         └──────┬──────┘                │
│                                                 │                        │
│  ROLLBACK                                       ▼                        │
│  ┌─────────────┐        Stop             ┌─────────────┐                │
│  │   v16.xx    │ ◄───────────────────────│   STOPPED   │                │
│  │  (Stopped)  │      (Preserve for      │  (Failed)   │                │
│  │             │       Debugging)        └──────┬──────┘                │
│  └──────┬──────┘                                │                        │
│         │                                       │                        │
│         │         Restore                       │                        │
│         │         from Snapshot                 │                        │
│         ▼                                       │                        │
│  ┌─────────────┐                                │                        │
│  │   v15.xx    │◄───────────────────────────────┘                        │
│  │  (Restored) │         Data: Point-in-time of snapshot                 │
│  │  (Active)   │         New endpoint/ARN                                  │
│  └─────────────┘                                                         │
│                                                                          │
│  ⚠️  DATA LOSS: Changes after snapshot timestamp are lost               │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

Timeline Example:
═══════════════════════════════════════════════════════════════════════════

Day 1:    02:00  Automated snapshot created (v15.xx)
          14:00  Upgrade started: v15.xx → v16.xx
          14:30  v16.xx running, testing begins
          15:00  ⚠️  Issues detected!

Day 1:    15:30  Rollback initiated
          15:35  v16.xx stopped (preserved)
          16:00  v15.xx restored from snapshot (02:00)
          16:05  DNS updated, application online

Result:   Data loss: 02:00-15:00 (13 hours)
          Downtime: ~30 minutes (restore + DNS propagation)
```

## Terraform Implementation

### Module Structure

```
modules/
├── rds_snapshot_rollback/    # NEW: Rollback management module
│   ├── main.tf              # Snapshot creation & restore logic
│   ├── variables.tf         # Rollback parameters
│   └── outputs.tf           # Restored instance details
```

### Usage Example

```hcl
# ============================================
# STEP 1: Create Pre-Upgrade Snapshot
# ============================================

module "pre_upgrade_snapshot" {
  source = "./modules/rds_snapshot_rollback"

  enabled = true
  action  = "create_snapshot"
  
  db_instance_id = module.rds_instance.id
  snapshot_name  = "${local.prefix_name}-pre-upgrade-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  
  tags = {
    Purpose     = "pre-upgrade-backup"
    Environment = "production"
    CreatedBy   = "terraform"
  }
}

# ============================================
# STEP 2: Perform Upgrade
# ============================================

module "rds_instance_upgraded" {
  source = "./modules/rds_instance"

  identifier     = "${local.prefix_name}-v16"
  engine         = "sqlserver-web"
  engine_version = "16.00"  # UPGRADE: 15.00 → 16.00
  
  # ... other configuration
  
  # Important: Keep snapshot until upgrade is validated
  depends_on = [module.pre_upgrade_snapshot]
}

# ============================================
# STEP 3: Execute Rollback (If Needed)
# ============================================
# This would typically be in a separate TF workspace
# or triggered manually after detecting issues

module "rollback_instance" {
  source = "./modules/rds_snapshot_rollback"

  enabled   = var.execute_rollback  # Set to true to trigger
  action    = "restore_from_snapshot"
  
  snapshot_id      = module.pre_upgrade_snapshot.snapshot_id
  new_identifier   = "${local.prefix_name}-rollback"
  
  # Restore all original settings
  instance_class   = "db.t3.medium"
  engine           = "sqlserver-web"
  engine_version   = "15.00.4198.2.v1"  # Original version
  
  db_subnet_group_name   = module.rds_networking_data.db_subnet_group_name
  vpc_security_group_ids = module.rds_networking_data.security_group_ids
  
  username = "admin"
  password = var.db_password
}
```

### Variables Reference

```hcl
variable "enabled" {
  description = "Enable or disable the rollback module"
  type        = bool
  default     = false
}

variable "action" {
  description = "Action to perform: 'create_snapshot' or 'restore_from_snapshot'"
  type        = string
  default     = "create_snapshot"
  
  validation {
    condition     = contains(["create_snapshot", "restore_from_snapshot"], var.action)
    error_message = "Action must be either 'create_snapshot' or 'restore_from_snapshot'."
  }
}

variable "snapshot_retention_days" {
  description = "Number of days to retain the snapshot"
  type        = number
  default     = 7
}

variable "skip_final_snapshot_on_rollback" {
  description = "Skip final snapshot when terminating failed upgrade instance"
  type        = bool
  default     = true
}
```

## Rollback Procedure Checklist

### Pre-Upgrade
- [ ] Enable snapshot creation (`create_pre_upgrade_snapshot = true`)
- [ ] Verify snapshot retention policy
- [ ] Document current instance configuration
- [ ] Notify stakeholders of maintenance window
- [ ] Ensure sufficient storage for snapshot

### During Upgrade
- [ ] Monitor upgrade progress via AWS Console/CLI
- [ ] Verify application connectivity post-upgrade
- [ ] Run smoke tests on new version
- [ ] Monitor CloudWatch metrics for anomalies

### If Rollback Required
- [ ] Set `execute_rollback = true`
- [ ] Run `terraform apply` to create restored instance
- [ ] Update DNS records to point to restored instance
- [ ] Verify data integrity on restored instance
- [ ] Notify team of rollback completion
- [ ] Analyze upgrade failure root cause

### Post-Rollback Cleanup
- [ ] Delete failed upgrade instance (if not done automatically)
- [ ] Archive logs from failed upgrade attempt
- [ ] Update documentation with lessons learned
- [ ] Schedule retry of upgrade with fixes applied

## Pros and Cons

### Advantages ✅
- **Simple**: Easy to understand and implement
- **Cost-effective**: No running duplicate instances
- **Reliable**: AWS snapshots are durable and tested
- **Fast setup**: Minimal additional infrastructure needed

### Disadvantages ⚠️
- **Downtime**: Restore process takes 10-60 minutes depending on DB size
- **Data loss**: Changes made after snapshot are lost
- **Manual process**: Requires human intervention to trigger
- **New instance**: Different ARN/endpoint may require config updates

## When to Use This Strategy

✅ **Recommended for:**
- Development and testing environments
- Small to medium databases (< 100 GB)
- Batch processing systems with flexible RTO
- Non-critical applications with defined maintenance windows
- Initial upgrade testing and validation

❌ **Not recommended for:**
- High-availability production systems requiring < 15 min RTO
- Large databases (> 500 GB) where restore takes hours
- Real-time systems with continuous data ingestion
- Financial/transactional systems requiring zero data loss

## Alternative: Blue/Green Deployment

For zero-downtime rollback capability, consider implementing the Blue/Green deployment strategy instead. This maintains two running instances and uses DNS switching for instant rollback.

See [Blue/Green Strategy Documentation](./BLUE_GREEN_STRATEGY.md) *(if created)* for details.

## Monitoring and Alerting

Set up CloudWatch alarms to detect issues that might trigger a rollback:

```hcl
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.prefix_name}-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU utilization high after upgrade - consider rollback"
  
  dimensions = {
    DBInstanceIdentifier = module.rds_instance.id
  }
}
```

## Cost Considerations

| Component | Cost | Notes |
|-----------|------|-------|
| Snapshot Storage | $0.095/GB/month | Charged until deleted |
| Restore Operation | Free | No charge for restore |
| New Instance | Standard RDS pricing | Billed during restore time |
| Data Transfer | $0.09/GB | If cross-region restore |

**Example**: 100 GB database snapshot = ~$9.50/month retention cost

## Best Practices

1. **Always snapshot before major upgrades** - Even if you have automated backups
2. **Test restore procedure** - Practice in dev environment before production
3. **Document rollback decision criteria** - When should you rollback vs. fix forward?
4. **Keep snapshots for at least 7 days** - Allows time for issues to surface
5. **Tag snapshots clearly** - Include date, version, and purpose
6. **Monitor storage costs** - Delete old snapshots after successful upgrades
7. **Have a communication plan** - Notify team before, during, and after rollback

## References

- [AWS RDS Snapshots Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_CreateSnapshot.html)
- [AWS RDS Restore from Snapshot](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_RestoreFromSnapshot.html)
- [Terraform aws_db_snapshot](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_snapshot)
- [Terraform aws_db_instance restore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance#restoring-from-a-snapshot)
