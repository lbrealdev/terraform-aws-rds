# RDS Storage Configuration Guide

This guide covers RDS storage types, migration strategies, performance considerations, and cost optimization.

For sizing **equivalent** storage Terraform settings when changing type
(**io1/io2 ↔ gp3**) from CloudWatch demand, see
[storage-performance-measurement.md](./storage-performance-measurement.md) and
[`scripts/measure-rds-storage.sh`](../scripts/measure-rds-storage.sh)
([usage](../scripts/README.md)).

## Overview

AWS RDS supports multiple storage types with different performance characteristics and pricing models:

| Storage Type | Use Case | IOPS | Throughput | Base Cost |
|--------------|----------|------|------------|-----------|
| **gp2** | General purpose workloads | 3 IOPS/GB (up to 16K) | 125 MB/s at 1TB+ | Baseline |
| **gp3** | Cost-effective, performance-tunable | 3K baseline (up to 16K) | 125 MB/s baseline (up to 1K) | ~20% cheaper than gp2 |
| **io1** | High-performance, IOPS-intensive | 1K-64K provisioned | 256 MB/s per 1K IOPS | Higher cost |
| **io2** | Highest performance, critical workloads | 1K-64K provisioned | 256 MB/s per 1K IOPS | Highest cost |
| **standard** | Legacy, development/testing only | 40-100 IOPS | ~40 MB/s | Lowest cost |

## Quick Reference

### When to Use Each Storage Type

**gp3** (Recommended for most production workloads):
- Cost-optimized alternative to gp2
- Tunable IOPS and throughput
- Best balance of price and performance
- Good for: web apps, microservices, general databases

**gp2**:
- Legacy workloads
- Simple setups without performance tuning needs
- Good for: development, small production databases

**io1/io2**:
- IOPS-intensive workloads
- Consistent low-latency requirements
- Good for: high-transaction OLTP, analytics, gaming

**standard**:
- Legacy compatibility only
- Non-critical, low-traffic workloads
- Good for: testing only

## Configuration Examples

### GP3 (Recommended)

```hcl
# terraform.tfvars
db_instance_storage_type       = "gp3"
db_instance_storage_throughput = 300  # 125-1000 MB/s
db_instance_iops               = 3000 # Optional, 3000-16000
```

**GP3 Benefits:**
- Baseline performance: 3,000 IOPS, 125 MB/s throughput
- Tunable: increase IOPS to 16,000 and throughput to 1,000 MB/s
- ~20% cheaper than gp2 for same storage size
- Better price/performance ratio

### GP2 (Default)

```hcl
# terraform.tfvars
db_instance_storage_type       = "gp2"
db_instance_storage_throughput = null
db_instance_iops               = null
```

**GP2 Characteristics:**
- IOPS scale with storage size (3 IOPS per GB, up to 16,000)
- Throughput: 125 MB/s at 1TB+ storage
- Simpler configuration (no IOPS/throughput parameters)

### IO1/IO2 (High Performance)

```hcl
# terraform.tfvars
db_instance_storage_type       = "io1"
db_instance_storage_throughput = null
db_instance_iops               = 5000 # 1000-64000
```

**IO1/IO2 Benefits:**
- Provisioned IOPS guarantee consistent performance
- Higher throughput (256 MB/s per 1,000 IOPS)
- Best for IOPS-intensive applications

## Migration: GP2 → GP3

### Migration Benefits

| Metric | GP2 (100GB) | GP3 (100GB) | Improvement |
|--------|-------------|-------------|-------------|
| IOPS | 300 (3×GB) | 3,000 (baseline) | 10× |
| Throughput | ~125 MB/s* | 125 MB/s (baseline) | Equal |
| Monthly Cost** | $23.00 | $18.40 | 20% cheaper |

\* GP2 throughput ramps up with storage size (125 MB/s at 1TB+)
\*\* Pricing example: eu-central-1 region, may vary

### Migration Process

**Step 1: Modify Configuration**

```hcl
# terraform.tfvars
db_instance_storage_type       = "gp3"
db_instance_storage_throughput = 125  # Start with baseline
db_instance_iops               = null # Use baseline IOPS
```

**Step 2: Apply Changes**

```bash
terraform plan
terraform apply
```

**Step 3: Monitor Performance**

After migration, monitor CloudWatch metrics:
- `BurstBalance` - GP3 burst credits (should be high if healthy)
- `ReadIOPS`, `WriteIOPS` - Baseline vs actual IOPS
- `ReadThroughput`, `WriteThroughput` - Throughput utilization

### Migration Downtime

- **No downtime**: Storage type changes are applied during the next maintenance window
- **Immediate apply**: Set `db_apply_immediately = true` to apply instantly (brief availability impact)
- **Rollback safe**: Can revert to gp2 if needed (same process)

### When to Increase IOPS/Throughput

Increase `db_instance_storage_throughput` or `db_instance_iops` if:

1. **High BurstBalance usage** (>70% sustained)
2. **IOPS/throughput throttling** in CloudWatch
3. **Performance degradation** during peak loads

**Example: Scale up for high-traffic**

```hcl
db_instance_storage_type       = "gp3"
db_instance_storage_throughput = 500  # Increased from 125
db_instance_iops               = 5000 # Increased from 3000
```

## Performance Considerations

### IOPS Allocation

| Storage Type | Default IOPS | Max IOPS | Cost Model |
|--------------|--------------|----------|------------|
| gp2 | 3 × allocated_storage (GB) | 16,000 | Included in storage cost |
| gp3 | 3,000 baseline | 16,000 | Baseline included, extra IOPS billed separately |
| io1 | Must provision | 64,000 | Per provisioned IOPS |
| io2 | Must provision | 64,000 | Per provisioned IOPS |

### Throughput Allocation

| Storage Type | Default Throughput | Max Throughput |
|--------------|-------------------|----------------|
| gp2 | Scales with storage (125 MB/s at 1TB+) | Limited by IOPS |
| gp3 | 125 MB/s baseline | 1,000 MB/s |
| io1/io2 | 256 MB/s per 1,000 IOPS | 1,000 MB/s at 4K+ IOPS |

### Cost Optimization

**Rule of Thumb: Start with GP3**

1. Use GP3 with baseline performance (3K IOPS, 125 MB/s)
2. Monitor CloudWatch metrics for 1-2 weeks
3. Scale up IOPS/throughput only if needed
4. IO1/IO2 only for proven IOPS-intensive workloads

**Cost Comparison (100GB, eu-central-1):**

| Storage Type | Monthly Cost | Notes |
|--------------|--------------|-------|
| gp2 | $23.00 | Includes IOPS |
| gp3 (baseline) | $18.40 | ~20% cheaper, better baseline |
| gp3 (scaled: 5K IOPS, 250 MB/s) | $23.60 | Slightly more than gp2, better performance |
| io1 (5K IOPS) | $36.00 | ~56% more expensive |

## Validation Rules

All storage configurations are validated automatically:

```hcl
# GP3 validation
db_instance_storage_type == "gp3" 
&& db_instance_storage_throughput >= 125 
&& db_instance_storage_throughput <= 1000

# IO1/IO2 validation
db_instance_storage_type == "io1" || "io2"
&& db_instance_iops >= 1000 
&& db_instance_iops <= 64000
```

**Invalid configurations will fail during `terraform plan`:**

```bash
Error: db_instance_storage_throughput for gp3 must be between 125 and 1000
```

## Monitoring and Alerts

### CloudWatch Metrics to Monitor

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `BurstBalance` | GP2/GP3 burst credits remaining | < 20% for 5+ minutes |
| `ReadIOPS` | Read operations per second | N/A (monitor trends) |
| `WriteIOPS` | Write operations per second | N/A (monitor trends) |
| `ReadThroughput` | Read throughput in MB/s | N/A (monitor trends) |
| `WriteThroughput` | Write throughput in MB/s | N/A (monitor trends) |
| `CPUUtilization` | Database CPU usage | > 80% for 10+ minutes |

### Recommended CloudWatch Alarms

```hcl
resource "aws_cloudwatch_metric_alarm" "gp3_burst_balance" {
  alarm_name          = "${var.prefix_name}-rds-gp3-burst-balance"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "BurstBalance"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "GP3 burst balance below 20%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
```

## FAQ

**Q: Can I change storage type without downtime?**
A: Yes, storage type changes are applied during the maintenance window. Use `db_apply_immediately = true` for immediate changes (brief impact).

**Q: What happens if I don't set IOPS for GP3?**
A: GP3 uses baseline IOPS (3,000) if `db_instance_iops` is `null`.

**Q: What happens if I don't set throughput for GP3?**
A: GP3 uses baseline throughput (125 MB/s) if `db_instance_storage_throughput` is `null`. This is the default value when not specified.

**Q: Is GP3 always cheaper than GP2?**
A: For most cases, yes (~20% cheaper). However, if you provision high IOPS/throughput on GP3, cost may exceed GP2.

**Q: Can I revert from GP3 to GP2?**
A: Yes, change `db_instance_storage_type` back to `"gp2"` and apply. Same process as GP2→GP3.

**Q: Should I use IO1 or IO2?**
A: IO2 is recommended for new deployments (better performance, similar cost). IO1 is for legacy compatibility.

**Q: How do I know if I need more IOPS?**
A: Monitor CloudWatch metrics. If `BurstBalance` stays low or you see throttling alerts, increase IOPS/throughput.

## Related Documentation

- [AWS RDS Storage](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html)
- [GP3 Storage Pricing](https://aws.amazon.com/rds/general-purpose-ssd/)
- [Rollback Strategy](./rollbacks-snapshot-strategy.md)
- [RDS Options Reference](./rds-options-reference.md)

## License

MIT