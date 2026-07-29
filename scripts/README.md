# scripts

## `measure-rds-storage.sh`

Assess whether an existing RDS instance on **io1/io2** is a good candidate for
**gp3** migration. Collects CloudWatch demand, sizes a gp3 equivalent, estimates
monthly cost, and prints a verdict plus a Terraform snippet.

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
| `--days` | `14` | CloudWatch lookback days |
| `--region` | `$AWS_DEFAULT_REGION` or `us-east-1` | AWS region |
| `--profile` | — | AWS CLI profile |
| `--headroom` | `1.2` | Sizing multiplier on p99 demand |
| `--rate-gp3-gb` | `0.115` | gp3 storage $/GB-mo |
| `--rate-gp3-iops` | `0.02` | gp3 IOPS $ above baseline |
| `--rate-gp3-tp` | `0.08` | gp3 throughput $/MiB/s above baseline |
| `--rate-piops-gb` | `0.125` | io1/io2 storage $/GB-mo |
| `--rate-piops` | `0.10` | io1/io2 provisioned IOPS $ |
| `--format` | `table` | `table` \| `json` \| `markdown` |
| `-h`, `--help` | — | Show help |

### Examples

```bash
./scripts/measure-rds-storage.sh --db-instance my-db-prod

./scripts/measure-rds-storage.sh --db-instance my-db-prod --days 3 --format json

./scripts/measure-rds-storage.sh --db-instance my-db-prod \
  --region eu-west-1 --profile prod
```

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | OK |
| 1 | Usage / argument error |
| 2 | AWS / dependency error |
| 3 | Unsupported storage type (not io1/io2) |

### Notes

- Only supports instances currently on `io1` or `io2`.
- Reported “p99” values are percentiles of CloudWatch **period averages** (5 min
  or 1 min), not raw-sample p99.
- Sub-ms latency is a **warning** only — confirm any hard SLA with the app owner
  before staying on PIOPS.
- Cloud-agent / CI environments without AWS credentials cannot run this script;
  use a workstation or pipeline with access to the target account and region.
