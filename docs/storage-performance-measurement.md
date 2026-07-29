# Storage Performance Measurement — Size Terraform Storage Knobs from Demand

A measurement-driven methodology to size **equivalent** RDS storage settings when
changing storage type (`io1`/`io2` ↔ `gp3`), so performance is not undersized.
Cost impact is informational.

## Overview / Use Case

| Current | Default target | Terraform knobs to set |
|---------|----------------|------------------------|
| `io1` / `io2` | `gp3` | `db_instance_storage_type`, `db_instance_iops`, `db_instance_storage_throughput` |
| `gp3` | `io2` | `db_instance_storage_type`, `db_instance_iops` (`throughput` = `null`) |

**Goal:** use CloudWatch **demand** (not the provisioned ceiling alone) to
recommend destination settings, then compare estimated monthly cost.

**Automation:** [`scripts/measure-rds-storage.py`](../scripts/measure-rds-storage.py)
(uv + boto3; see [`scripts/README.md`](../scripts/README.md)).

This does not replace general storage guidance — see
[storage-guide.md](./storage-guide.md).

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| `uv` | Via `mise install` (`mise.toml`) or [astral.sh/uv](https://docs.astral.sh/uv/) |
| AWS credentials | boto3 credential chain (env, profile, instance role, …) |
| IAM | `rds:DescribeDBInstances`, `cloudwatch:GetMetricData` |

> [!NOTE]
> Cloud-agent / CI environments without real AWS credentials cannot run this
> loop. Per [`AGENTS.md`](../AGENTS.md), only the offline Terraform loop is
> available there. Pass `-r` / `--region` (or set `AWS_REGION` /
> `AWS_DEFAULT_REGION`) to match the instance’s region.

## Step 1 — Capture Current Configuration

```bash
aws rds describe-db-instances \
  --db-instance-identifier <id> \
  --region <region> \
  --query 'DBInstances[0].{Engine,StorageType,AllocatedStorage,Iops,StorageThroughput,MultiAZ,DBInstanceClass,MaxAllocatedStorage,PendingModifiedValues,PreferredMaintenanceWindow,DedicatedLogVolume,DBInstanceStatus}' \
  --output json
```

Record: engine, storage type, allocated GiB, IOPS, throughput (gp3), Multi-AZ,
instance class, DLV. **DLV blocks gp3** (io1/io2 only).

## Step 2 — Collect CloudWatch Metrics

| Metric | Namespace | Statistic | Period | Why |
|--------|-----------|-----------|--------|-----|
| `ReadIOPS` / `WriteIOPS` | AWS/RDS | Average → client p99 | 5 min (14d) / 1 min (≤3d) | Peak IOPS demand |
| `ReadThroughput` / `WriteThroughput` | AWS/RDS | Average → p99/max | same | Throughput demand |
| `ReadLatency` / `WriteLatency` | AWS/RDS | Average → p99 | same | App sensitivity (note only) |
| `DiskQueueDepth` | AWS/RDS | Average | same | I/O pressure note |
| `CPUUtilization` / `FreeableMemory` / `CPUCreditBalance` | AWS/RDS | Average/max | same | Context |

### Retention / period rules

- **14-day lookback:** period `300` (5 min)
- **≤3-day lookback:** period `60` (1 min) — useful for smoke tests (`--days 1`)
- Script “p99” = percentile of CloudWatch **period averages**, not raw samples

Derive:

- `TotalIOPS = ReadIOPS + WriteIOPS`
- `TotalThroughput` bytes/s → MiB/s ÷ 1,048,576

## Step 3 — Interpret the Metrics

| Signal | Interpretation |
|--------|----------------|
| `p99_total_iops / provisioned_iops < 0.5` (on PIOPS) | Over-provisioned vs ceiling — demand still drives destination size |
| `DiskQueueDepth` high vs IOPS | Do not undersize destination |
| p99 latency &lt; 1 ms | **Note only** — confirm hard sub-ms SLA with app owner |
| Empty / near-zero series | Stopped or idle — verify traffic before applying settings |
| High CPU + low IOPS | Bottleneck may be compute, not storage type |

## Step 4 — Size the Destination

`need_iops = p99_total_iops × headroom` (default 1.2)  
`need_tp   = p99_total_tp   × headroom`

### Terraform knobs by type

| Setting | gp3 | io2 |
|---------|-----|-----|
| `db_instance_storage_type` | `"gp3"` | `"io2"` |
| `db_instance_iops` | Optional (baseline or tuned) | Required (provisioned) |
| `db_instance_storage_throughput` | Optional (baseline or tuned) | `null` |

### gp3 performance by engine / size

Limits match current
[Amazon RDS DB instance storage](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html):

| Engine | Storage | Included baseline | Provisionable IOPS | Provisionable throughput |
|--------|---------|-------------------|--------------------|--------------------------|
| MySQL, MariaDB, PostgreSQL, Db2 | 20–399 GiB | 3,000 / 125 | N/A (baseline only) | N/A |
| MySQL, MariaDB, PostgreSQL, Db2 | 400–65,536 GiB | **12,000 / 500** | 12,000–64,000 | 500–4,000 MiB/s |
| Oracle | 20–199 GiB | 3,000 / 125 | N/A | N/A |
| Oracle | 200–65,536 GiB | **12,000 / 500** | 12,000–64,000 | 500–4,000 MiB/s |
| SQL Server | any size | 3,000 / 125 | 3,000–80,000 | 125–2,000 MiB/s |

**→ gp3:** if demand ≤ included baseline → recommend `null` / `null`. If below
stripe and demand &gt; baseline → note: grow storage or keep PIOPS. Enforce
`throughput ≤ 0.25 × iops` when tuning.

**→ io2:** provision `need_iops` (rounded), clamp to methodology range
1,000–256,000; `storage_throughput = null`. Destination family is **io2** (not io1).

## Step 5 — Compare Costs (informational)

Rates are region-parameterized (defaults = us-east-1 reference).

| Type | Storage $/GB-mo | IOPS | Throughput |
|------|-----------------|------|------------|
| gp3 | 0.115 | +0.02 above **applicable** baseline | +0.08 above **applicable** baseline |
| io1 / io2 | 0.125 | 0.10 per provisioned IOPS-mo | — |

Applicable gp3 baseline: **3K/125** below stripe or SQL Server; **12K/500** when
striped. Multi-AZ ×2 on storage + IOPS + throughput charges.

```
cost_delta_pct = (current − recommended) / current × 100
# positive ⇒ recommended config is cheaper
```

## Step 6 — Limits and Notes (not a migrate/stay verdict)

| Condition | Note |
|-----------|------|
| Dedicated Log Volume + target gp3 | **BLOCKER** — cannot recommend gp3 |
| `need_iops` &gt; destination max | Destination may not meet demand |
| Storage &lt; stripe, needs &gt; 3K/125 for gp3 | Grow storage or keep PIOPS |
| Sub-ms p99 latency | Confirm hard SLA with app owner |
| Empty / stopped metrics | Verify traffic before applying |

The script prints **recommended Terraform** + **cost delta** + **notes**. It does
not emit MIGRATE / STAY decisions.

## Worked Examples

### A — io2 → gp3

**Current:** PostgreSQL, io2, 20,000 IOPS, 500 GiB, Multi-AZ, us-east-1.  
**Observed:** p99 TotalIOPS = 7,200; throughput under 500 MiB/s.

```
need_iops = 7200 × 1.2 = 8640  ≤ striped baseline 12K/500
→ db_instance_storage_type = "gp3"
→ db_instance_iops = null
→ db_instance_storage_throughput = null
```

Cost (Multi-AZ ×2): io2 ≈ $4,125/mo → gp3 baseline ≈ $115/mo (informational).

### B — gp3 → io2

**Current:** PostgreSQL, gp3 baseline, 500 GiB, Multi-AZ.  
**Observed:** p99 TotalIOPS = 7,200.

```
need_iops = 7200 × 1.2 = 8640 → round to 8700
→ db_instance_storage_type = "io2"
→ db_instance_iops = 8700
→ db_instance_storage_throughput = null
```

Cost rises vs gp3 baseline (informational); use when you need PIOPS/DLV or
explicit provisioned IOPS.

## Applying in Terraform

```hcl
# Example: PIOPS → gp3 baseline
db_instance_storage_type       = "gp3"
db_instance_iops               = null
db_instance_storage_throughput = null

# Example: gp3 → io2
db_instance_storage_type       = "io2"
db_instance_iops               = 8700
db_instance_storage_throughput = null
```

Apply with `just plan` / `just apply`. Storage type changes typically use the
maintenance window unless `db_apply_immediately = true`. See
[storage-guide.md](./storage-guide.md).

## Post-Change Validation

Re-check ≥ **7 days**:

| Check | Expectation |
|-------|-------------|
| `DiskQueueDepth` | Not rising vs pre-change under similar load |
| Latency p99 | Within app SLA |
| p99 TotalIOPS | Under destination provisioned / baseline ceiling |
| `BurstBalance` | **Not** a gp3 health signal after leaving PIOPS |

## FAQ

**Wrong region / DBInstanceNotFound**  
Pass `-r` / `--region` (script prefers `AWS_REGION`, then `AWS_DEFAULT_REGION`, else
`us-east-1`).

**Slow runs**  
Progress is on stderr. Metrics fetch depends on AWS; local stats should be near-instant.
Use `-d 1` for a smoke test.

**Exit code 3**  
Unsupported type (not io1/io2/gp3) or invalid `--target` for current type.

**Why not recommend io1?**  
This methodology uses **io2** as the PIOPS destination family.

**Requires uv**  
Install via `mise install` (see `mise.toml`) or https://docs.astral.sh/uv/

## References

- [Amazon RDS DB instance storage](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html)
- [CloudWatch metrics for Amazon RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/monitoring-cloudwatch.html)
- [AWS Pricing Calculator](https://calculator.aws/)
- [Storage Guide (this repo)](./storage-guide.md)
- [Script README](../scripts/README.md)

## License

MIT
