# Storage Performance Measurement — Size Terraform Storage Knobs from Demand

A measurement-driven methodology to size **equivalent** RDS storage settings when
changing storage type (`io1`/`io2` ↔ `gp3`), so performance is not undersized.
Cost impact is informational.

## Overview / Use Case

| Current | Default target | Terraform knobs to set |
|---------|----------------|------------------------|
| `io1` / `io2` | `gp3` | `storage_type`, `iops`, `storage_throughput` |
| `gp3` | `io2` | `storage_type`, `iops` (`storage_throughput` = `null`) |

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
| IAM | `rds:DescribeDBInstances`, `cloudwatch:GetMetricData`, optional `pricing:GetProducts` |

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

Primary metrics (same as console / Amazon Q validation):

| Metric | Stats collected | Why |
|--------|-----------------|-----|
| `ReadIOPS` / `WriteIOPS` | **Average** and **Maximum** | Peak + typical demand |
| `ReadThroughput` / `WriteThroughput` | **Average** and **Maximum** | Peak + typical throughput |
| Latency / queue / CPU | Average | Context / notes |

Default period: `300` (5 min) for lookbacks &gt; 3 days; `60` for ≤3 days.

## Step 3 — Interpret the Metrics

| Signal | Interpretation |
|--------|----------------|
| High **Maximum** Read+Write IOPS | Drives default sizing (`--size-from maximum`) |
| p99 of Averages ≪ Maximum | Spiky workload — Maximum-based sizing is safer for “no regression” |
| Instance class EBS baseline/max | Caps what storage can deliver (e.g. db.m5.xlarge baseline 6000 IOPS) |
| Empty / near-zero series | Stopped or idle — verify traffic before applying settings |

## Step 4 — Size the Destination

**Default (`--size-from maximum`, aligns with console/Q/Rovo):**

```
peak_iops = max(ReadIOPS) + max(WriteIOPS)
peak_tp   = (max(ReadThroughput) + max(WriteThroughput)) / 1,048,576   # MiB/s
need_iops = peak_iops × headroom (default 1.2)
need_tp   = peak_tp   × headroom
```

Then clamp to **DB instance class EBS max**, then apply gp3/io2 engine rules.

Optional: `--size-from p99-average` uses p99 of Average totals instead (older behavior).

### Terraform knobs by type

| Setting | gp3 | io2 |
|---------|-----|-----|
| `storage_type` | `"gp3"` | `"io2"` |
| `iops` | Optional (baseline or tuned) | Required (provisioned) |
| `storage_throughput` | Optional (baseline or tuned) | `null` |

Map these generic names to your module variables as needed (this repo uses
`db_instance_*` prefixes at the root stack).

### What `null` means (gp3 baseline)

For gp3, **`iops = null` and `storage_throughput = null` mean “use the included
baseline”**. When Maximum-based demand exceeds baseline, the script recommends
**concrete** values (common for SQL Server, e.g. 6000 IOPS / 500 MiB/s).

- SQL Server baseline: **3,000 IOPS / 125 MiB/s** (tunable at any size)
- Non–SQL Server below stripe: **3,000 / 125** (baseline only)
- Non–SQL Server at/above stripe: **12,000 / 500**

### Instance class EBS caps

RDS cannot deliver more than the instance class EBS limit. Example:
`db.m5.xlarge` ≈ baseline **6000** IOPS / max **18750** IOPS, max throughput
~**594** MiB/s. The script clamps recommendations and warns when demand exceeds
the class.

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

The script calls the **AWS Price List Query API** (`pricing:GetProducts`) for the
instance region when possible, and falls back to us-east-1 reference constants.
IAM: `pricing:GetProducts`.

Multi-AZ ×2 on storage + IOPS + throughput charges.

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

### A — PostgreSQL io2 → gp3 (striped baseline)

**Current:** PostgreSQL, io2, 20,000 IOPS, 500 GiB, Multi-AZ, us-east-1.  
**Observed Maximum:** peak Read+Write IOPS ≈ 7,200; peak throughput under 500 MiB/s.

```
need_iops = 7200 × 1.2 = 8640  ≤ striped baseline 12K/500
→ storage_type = "gp3"
→ iops = null                 # included baseline: 12000 IOPS
→ storage_throughput = null   # included baseline: 500 MiB/s
```

Cost (Multi-AZ ×2, Price List or fallback rates): io2 ≈ $4,125/mo → gp3 baseline ≈ $115/mo (informational).

### B — SQL Server io2 → gp3 (Maximum-based)

**Current:** SQL Server, io2, db.m5.xlarge, Multi-AZ.  
**Observed Maximum:** peak Read+Write IOPS and throughput imply need ≈ 6000 IOPS /
500 MiB/s after headroom (above gp3 baseline 3K/125; within class max).

```
→ storage_type       = "gp3"
→ iops               = 6000
→ storage_throughput = 500
```

Instance class baseline (6000 IOPS on m5.xlarge) often aligns with this class of
recommendation when sizing from Maximum peaks.

## Applying settings

```hcl
# Example: PIOPS → gp3 baseline (null = included performance)
storage_type       = "gp3"
iops               = null  # included baseline: 12000 IOPS (striped example)
storage_throughput = null  # included baseline: 500 MiB/s

# Example: gp3 → io2
storage_type       = "io2"
iops               = 8700
storage_throughput = null
```

Apply with `just plan` / `just apply`. Storage type changes typically use the
maintenance window unless `db_apply_immediately = true`. See
[storage-guide.md](./storage-guide.md).

## Post-Change Validation

Re-check ≥ **7 days**:

| Check | Expectation |
|-------|-------------|
| `DiskQueueDepth` | Not rising vs pre-change under similar load |
| Latency (Average / p99 of averages) | Within app SLA |
| Peak IOPS (Maximum Read+Write) | Under destination provisioned / class max |
| Peak throughput | Under destination MiB/s / class max |
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
- [Hardware specifications for DB instance classes](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.DBInstanceClass.Summary.html)
- [Factors that affect DB instance performance (EBS)](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html#CHAP_Storage.Other.Factors)
- [CloudWatch metrics for Amazon RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/monitoring-cloudwatch.html)
- [AWS Price List Query API](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/using-price-list-query-api.html)
- [GetProducts API](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_pricing_GetProducts.html)
- [AWS Pricing Calculator](https://calculator.aws/)
- [Storage Guide (this repo)](./storage-guide.md)
- [Script README](../scripts/README.md)

## License

MIT
