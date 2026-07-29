# scripts

## `measure-rds-storage.py`

Size **equivalent RDS storage Terraform settings** from CloudWatch demand when
changing storage type. Implemented as a [uv inline script](https://docs.astral.sh/uv/guides/scripts/#declaring-script-dependencies)
(PEP 723) with `boto3`.

| Current | Default target | Terraform knobs |
|---------|----------------|-----------------|
| `io1` / `io2` | `gp3` | `storage_type`, `iops`, `storage_throughput` |
| `gp3` | `io2` | `storage_type`, `iops` (`storage_throughput` = `null`) |

### How sizing works (console / Q / Rovo aligned)

By default (`--size-from maximum`):

1. Fetch **Average** and **Maximum** for Read/Write IOPS and Read/Write Throughput.
2. Peak demand = `max(Read)+max(Write)` for IOPS and throughput (MiB/s).
3. `need_* = peak × headroom` (default 1.2).
4. Apply **DB instance class EBS caps** (e.g. `db.m5.xlarge` baseline 6000 IOPS / max 18750).
5. Map to gp3 or io2 rules (SQL Server gp3 is tunable at any size; baseline 3K/125).

Use `--size-from p99-average` for the older p99-of-Averages approach (display still
shows both Maximum peaks and p99 averages).

### What `null` means

For **gp3**, `iops = null` and `storage_throughput = null` mean **use the included
baseline** for that engine/size. When Maximum-based demand exceeds baseline (common
for SQL Server), the script recommends concrete values (e.g. `6000` / `500`).

**Notes** only appear for warnings (DLV, class clamp, empty metrics, etc.).

### Cost

Best-effort **AWS Price List Query API** rates for the instance region (IAM:
`pricing:GetProducts`). Falls back to us-east-1 reference constants if unavailable.

Full methodology:
[docs/storage-performance-measurement.md](../docs/storage-performance-measurement.md)

### Prerequisites

- [`uv`](https://docs.astral.sh/uv/) (`mise install` via `mise.toml`)
- AWS credentials (boto3 chain)
- IAM: `rds:DescribeDBInstances`, `cloudwatch:GetMetricData`, optional `pricing:GetProducts`

### Usage

```bash
./scripts/measure-rds-storage.py -i <id> -r <region> [options]
```

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--db-instance` | `-i` | required | RDS DB instance identifier |
| `--region` | `-r` | env / `us-east-1` | AWS region |
| `--profile` | `-p` | — | AWS profile |
| `--days` | `-d` | `14` | CloudWatch lookback |
| `--target` | `-t` | auto | `gp3` or `io2` |
| `--size-from` | | `maximum` | `maximum` \| `p99-average` |
| `--format` | `-f` | `table` | `table` \| `json` \| `markdown` |
| `--headroom` | | `1.2` | Demand multiplier |

### Examples

```bash
./scripts/measure-rds-storage.py -i my-db -r eu-west-1 -d 14
./scripts/measure-rds-storage.py -i my-db -r eu-west-1 -d 90 --size-from maximum
./scripts/measure-rds-storage.py -i my-db -r eu-west-1 --size-from p99-average -f json
```

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | OK |
| 1 | Usage error |
| 2 | AWS error |
| 3 | Unsupported storage / invalid direction |
