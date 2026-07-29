# scripts

## `measure-rds-storage.sh`

Size **equivalent RDS storage Terraform settings** from CloudWatch demand when
changing storage type:

| Current | Default target | Terraform knobs |
|---------|----------------|-----------------|
| `io1` / `io2` | `gp3` | `storage_type`, `iops`, `storage_throughput` |
| `gp3` | `io2` | `storage_type`, `iops` (`throughput` = `null`) |

Goal: recommend destination IOPS/throughput (or baseline) so the change does
**not** undersize performance. Cost delta is informational.

Full methodology:
[docs/storage-performance-measurement.md](../docs/storage-performance-measurement.md)

### Prerequisites

- AWS CLI v2 (`aws --version`)
- `jq`
- IAM: `rds:DescribeDBInstances`, `cloudwatch:GetMetricData`

### Usage

```bash
./scripts/measure-rds-storage.sh --db-instance <id> [options]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--db-instance` | (required) | RDS DB instance identifier |
| `--target` | auto | Destination: `gp3` or `io2` |
| `--days` | `14` | CloudWatch lookback (use `1` or `3` for smoke tests) |
| `--region` | `$AWS_REGION` → `$AWS_DEFAULT_REGION` → `us-east-1` | AWS region |
| `--profile` | — | AWS CLI profile |
| `--headroom` | `1.2` | Sizing multiplier on p99 demand |
| `--rate-gp3-gb` / `--rate-gp3-iops` / `--rate-gp3-tp` | us-east-1 refs | Override gp3 rates |
| `--rate-piops-gb` / `--rate-piops` | us-east-1 refs | Override io1/io2 rates |
| `--format` | `table` | `table` \| `json` \| `markdown` |
| `-h`, `--help` | — | Show help |

Progress messages go to **stderr**; the report goes to **stdout**.

### Examples

```bash
# Auto direction from current storage type (pass --region if not us-east-1)
./scripts/measure-rds-storage.sh --db-instance my-db-prod --region eu-west-1

# Faster smoke test
./scripts/measure-rds-storage.sh --db-instance my-db-prod --region eu-west-1 --days 1

# Explicit target
./scripts/measure-rds-storage.sh --db-instance my-db-prod --target gp3 --format json
```

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | OK |
| 1 | Usage / argument error |
| 2 | AWS / dependency error |
| 3 | Unsupported storage type or invalid direction |

### Notes

- Read-only: only `DescribeDBInstances` and `GetMetricData`.
- “p99” is a percentile of CloudWatch **period averages**, not raw-sample p99.
- Sub-ms latency is a **note** only — confirm any hard SLA with the app owner.
- PIOPS destination is always **io2** (not io1).
