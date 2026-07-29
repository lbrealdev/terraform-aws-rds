# scripts

## `measure-rds-storage.py`

Size **equivalent RDS storage Terraform settings** from CloudWatch demand when
changing storage type. Implemented as a [uv inline script](https://docs.astral.sh/uv/guides/scripts/#declaring-script-dependencies)
(PEP 723) with `boto3`.

| Current | Default target | Terraform knobs |
|---------|----------------|-----------------|
| `io1` / `io2` | `gp3` | `storage_type`, `iops`, `storage_throughput` |
| `gp3` | `io2` | `storage_type`, `iops` (`throughput` = `null`) |

Goal: recommend destination IOPS/throughput (or baseline) so the change does
**not** undersize performance. Cost delta is informational (us-east-1 reference
rates in the script).

Full methodology:
[docs/storage-performance-measurement.md](../docs/storage-performance-measurement.md)

### Prerequisites

- [`uv`](https://docs.astral.sh/uv/) (`mise install` installs it via `mise.toml`)
- AWS credentials (same chain as boto3 / AWS CLI)
- IAM: `rds:DescribeDBInstances`, `cloudwatch:GetMetricData`

### Usage

```bash
./scripts/measure-rds-storage.py -i <id> [options]
# or
uv run scripts/measure-rds-storage.py -i <id> [options]
```

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--db-instance` | `-i` | required | RDS DB instance identifier |
| `--region` | `-r` | `$AWS_REGION` → `$AWS_DEFAULT_REGION` → `us-east-1` | AWS region |
| `--profile` | `-p` | — | AWS profile |
| `--days` | `-d` | `14` | CloudWatch lookback (use `1` or `3` for smoke tests) |
| `--target` | `-t` | auto | `gp3` or `io2` |
| `--format` | `-f` | `table` | `table` \| `json` \| `markdown` |
| `--headroom` | | `1.2` | Demand multiplier |

Progress messages go to **stderr**; the report goes to **stdout**.

### Examples

```bash
./scripts/measure-rds-storage.py -i my-db-prod -r eu-west-1

./scripts/measure-rds-storage.py -i my-db-prod -r eu-west-1 -d 1

./scripts/measure-rds-storage.py -i my-db-prod -t gp3 -f json
```

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | OK |
| 1 | Usage / argument error |
| 2 | AWS error |
| 3 | Unsupported storage type or invalid direction |

### Notes

- Read-only AWS APIs only.
- “p99” is a percentile of CloudWatch **period averages**.
- PIOPS destination is always **io2** (not io1).
- First run downloads `boto3` into a uv-managed environment automatically.
