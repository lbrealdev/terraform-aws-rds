# Storage Performance Measurement — io1/io2 → gp3 Migration Assessment

A measurement-driven, reusable methodology for assessing whether an existing
provisioned-IOPS (io1/io2) RDS instance is a good candidate for gp3 migration.

## Overview / Use Case

This guide applies to **any** RDS instance currently on provisioned IOPS storage
(`io1` or `io2`) that you are considering moving to `gp3`. It does not replace
general storage configuration guidance — for storage types, gp2→gp3 migration,
and Terraform variable reference, see [storage-guide.md](./storage-guide.md).

**Goal:** use CloudWatch demand (not provisioned ceiling) to size a gp3
equivalent, estimate monthly savings, and produce a clear migrate / stay /
conditional verdict.

**Automation:** run [`scripts/measure-rds-storage.sh`](../scripts/measure-rds-storage.sh)
to collect metrics, apply the sizing rules below, and emit a ready-to-paste
Terraform snippet.

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| AWS CLI v2 | `aws --version` |
| `jq` | JSON parsing for describe + metric series |
| IAM | `rds:DescribeDBInstances`, `cloudwatch:GetMetricData` |
| Optional IAM | `pricing:GetProducts` if you later automate live rate lookup |

> [!NOTE]
> Cloud-agent / CI environments without real AWS credentials cannot run this
> measurement loop. Per [`AGENTS.md`](../AGENTS.md), only the offline Terraform
> loop (`just init`, `just validate`, `just fmt`) is available there. Run the
> script from a workstation or pipeline that has credentials for the target
> account and region.

## Step 1 — Capture Current Configuration

```bash
aws rds describe-db-instances \
  --db-instance-identifier <id> \
  --query 'DBInstances[0].{Engine,StorageType,AllocatedStorage,Iops,StorageThroughput,MultiAZ,DBInstanceClass,MaxAllocatedStorage,PendingModifiedValues,PreferredMaintenanceWindow,DedicatedLogVolume,DBInstanceStatus}' \
  --output json
```

Record at least: engine, storage type, allocated GiB, provisioned IOPS,
Multi-AZ, instance class, and whether a Dedicated Log Volume (DLV) is enabled.
DLV is an immediate **BLOCKER** for gp3 (see [Decision Matrix](#step-6--decision-matrix)).

## Step 2 — Collect CloudWatch Metrics

| Metric | Namespace | Statistic | Period | Why |
|--------|-----------|-----------|--------|-----|
| `ReadIOPS` | AWS/RDS | Average, Maximum, p99 | 5 min (14d) / 1 min (3d) | Peak read demand |
| `WriteIOPS` | AWS/RDS | Average, Maximum, p99 | same | Peak write demand |
| `ReadLatency` | AWS/RDS | Average, p99 | 5 min | App sensitivity |
| `WriteLatency` | AWS/RDS | Average, p99 | 5 min | App sensitivity |
| `ReadThroughput` | AWS/RDS | Average, Maximum | 5 min | Throughput demand |
| `WriteThroughput` | AWS/RDS | Average, Maximum | 5 min | Throughput demand |
| `DiskQueueDepth` | AWS/RDS | Average, Maximum | 5 min | I/O pressure |
| `CPUUtilization` | AWS/RDS | Average, Maximum | 5 min | Context |
| `FreeableMemory` | AWS/RDS | Average | 5 min | Context |
| `CPUCreditBalance` | AWS/RDS | Average | 5 min | Burstable class only |

### Retention / period rules

- **14-day lookback:** period `300` (5 min) — CloudWatch retains 5-minute data for 63 days
- **3-day lookback:** period `60` (1 min) — higher resolution for short windows
- Prefer **p99** for sizing (use p95 if you accept more risk); use **max** for peak headroom checks

Derive totals client-side (or via metric math):

- `TotalIOPS = ReadIOPS + WriteIOPS`
- `TotalThroughput = ReadThroughput + WriteThroughput` (bytes/s → MiB/s ÷ 1,048,576)

### Example: `get-metric-data`

```bash
START=$(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DB_ID="my-db-prod"

aws cloudwatch get-metric-data \
  --start-time "$START" \
  --end-time "$END" \
  --metric-data-queries '[
    {
      "Id": "riops",
      "MetricStat": {
        "Metric": {
          "Namespace": "AWS/RDS",
          "MetricName": "ReadIOPS",
          "Dimensions": [{"Name":"DBInstanceIdentifier","Value":"'"$DB_ID"'"}]
        },
        "Period": 300,
        "Stat": "Average"
      },
      "ReturnData": true
    },
    {
      "Id": "wiops",
      "MetricStat": {
        "Metric": {
          "Namespace": "AWS/RDS",
          "MetricName": "WriteIOPS",
          "Dimensions": [{"Name":"DBInstanceIdentifier","Value":"'"$DB_ID"'"}]
        },
        "Period": 300,
        "Stat": "Average"
      },
      "ReturnData": true
    },
    {
      "Id": "total_iops",
      "Expression": "riops + wiops",
      "Label": "TotalIOPS",
      "ReturnData": true
    }
  ]' \
  --output json
```

Repeat analogous queries for latency, throughput, queue depth, CPU, and memory.
The measurement script builds the full query set automatically.

## Step 3 — Interpret the Metrics

| Signal | Interpretation |
|--------|----------------|
| `p99_total_iops / provisioned_iops < 0.5` | Over-provisioned — strong cost-down candidate |
| `p99_total_iops / provisioned_iops > 0.8` | Working near the PIOPS ceiling — size carefully or stay |
| `DiskQueueDepth > 10 × (provisioned_iops / 10000)` | Sustained queue pressure — do not undersize gp3 |
| `ReadLatency` / `WriteLatency` p99 **&lt; 1 ms** sustained | Signal only — confirm with the app owner whether a hard sub-ms SLA exists; not an automatic stay |
| Near-zero series / empty datapoints | Stopped or idle instance — treat as decommission / low-traffic |
| High CPU + low IOPS | Bottleneck is compute, not storage type |

Rules of thumb used by the script:

- `p99_total_iops / provisioned_iops < 0.5` → over-provisioned (money insight)
- `DiskQueueDepth > 10 * (provisioned_iops / 10000)` → queue pressure
- `ReadLatency` / `WriteLatency` p99 &lt; 1 ms → warning note; confirm SLA with the app owner (does not auto-STAY)

> [!NOTE]
> Script “p99” values are percentiles of CloudWatch **period averages** (5 min or
> 1 min), not raw sample p99. Prefer that series for sizing; use **max** when you
> need peak headroom checks.

## Step 4 — Size the gp3 Equivalent

Limits below match current
[Amazon RDS DB instance storage](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html)
gp3 tables (verify against AWS docs if reading this later).

### gp3 performance by engine / size

| Engine | Storage | Included baseline | Provisionable IOPS | Provisionable throughput |
|--------|---------|-------------------|--------------------|--------------------------|
| MySQL, MariaDB, PostgreSQL, Db2 | 20–399 GiB | 3,000 IOPS / 125 MiB/s | N/A (baseline only) | N/A |
| MySQL, MariaDB, PostgreSQL, Db2 | 400–65,536 GiB | **12,000 IOPS / 500 MiB/s** | 12,000–64,000 | 500–4,000 MiB/s |
| Oracle | 20–199 GiB | 3,000 IOPS / 125 MiB/s | N/A (baseline only) | N/A |
| Oracle | 200–65,536 GiB | **12,000 IOPS / 500 MiB/s** | 12,000–64,000 | 500–4,000 MiB/s |
| SQL Server (all editions) | any size | 3,000 IOPS / 125 MiB/s | 3,000–80,000 | 125–2,000 MiB/s |

### gp3 constraints

- `throughput ≤ 0.25 × iops` — raise IOPS if violated (when both are provisioned above baseline)
- `iops ≤ 500 × storage_gb` — raise storage or fail the candidate
- **Below stripe threshold:** single volume, **baseline only** (3K / 125; not tunable)
- **At/above stripe threshold:** included baseline is **12K / 500**; do not provision below that floor when tuning
- **SQL Server:** no stripe threshold — tunable at any size; baseline remains 3K / 125

### Stripe thresholds by engine

| Engine | &lt; Stripe | ≥ Stripe | Tunable at/above stripe |
|--------|------------|----------|-------------------------|
| MySQL, MariaDB, PostgreSQL, Db2 | &lt; 400 GiB | ≥ 400 GiB | Yes (12K–64K IOPS) |
| Oracle | &lt; 200 GiB | ≥ 200 GiB | Yes (12K–64K IOPS) |
| SQL Server (all editions) | N/A (always tunable) | any size | Yes (up to 80K IOPS) |

### Sizing logic (pseudocode)

```
need_iops = p99_total_iops × headroom (default 1.2)
need_tp   = p99_total_tp   × headroom

if engine == sqlserver:
    base_iops, base_tp = 3000, 125
    max_iops, max_tp   = 80000, 2000
    if need_iops <= base_iops and need_tp <= base_tp:
        gp3_iops = null; gp3_tp = null
    else:
        gp3_iops = clamp(need_iops, base_iops, max_iops)
        gp3_tp   = clamp(need_tp, base_tp, max_tp)
elif storage_gb < stripe_threshold(engine):   # 400 GiB (200 for Oracle)
    if need_iops <= 3000 and need_tp <= 125:
        gp3_iops = null   # stay at baseline
        gp3_tp   = null
    else:
        # gp3 cannot deliver at this size
        # option A: grow storage to threshold
        # option B: stay on PIOPS
        gp3_iops = null  # flag: needs larger storage
        gp3_tp   = null
else:
    # Striped: included baseline is 12K / 500
    base_iops, base_tp = 12000, 500
    max_iops, max_tp   = 64000, 4000
    if need_iops <= base_iops and need_tp <= base_tp:
        gp3_iops = null; gp3_tp = null
    else:
        gp3_iops = clamp(need_iops, base_iops, max_iops)
        gp3_tp   = clamp(need_tp, base_tp, max_tp)
        # enforce gp3_tp ≤ 0.25 × gp3_iops
        if gp3_tp > 0.25 * gp3_iops:
            gp3_iops = max(gp3_iops, gp3_tp * 4)
```

Round recommended IOPS upward to a practical step (e.g. nearest 100)
before writing Terraform.

## Step 5 — Compare Costs

Rates are **region-parameterized**. Reference values below are for **us-east-1**
(rates verified **2026-07-29** — recompute for other regions or later dates).

| Type | Storage $/GB-mo | IOPS | Throughput |
|------|-----------------|------|------------|
| gp3 | 0.115 | +0.02/IOPS-mo above **applicable** baseline | +0.08/MiB/s-mo above **applicable** baseline |
| io1 | 0.125 | 0.10 per provisioned IOPS-mo | — |
| io2 | 0.125 | 0.10 per provisioned IOPS-mo | — |

**Applicable gp3 baseline for billing extras:**

- Below stripe (or SQL Server): **3,000 IOPS / 125 MiB/s**
- At/above stripe (MySQL, MariaDB, PostgreSQL, Db2, Oracle): **12,000 IOPS / 500 MiB/s**

```
current_cost = gb × rate_storage(type) + prov_iops × rate_piops(type)
gp3_cost     = gb × 0.115
             + max(0, bill_iops − base_iops) × 0.02
             + max(0, bill_tp   − base_tp)   × 0.08
multi_az     → multiply storage + IOPS + throughput charges × 2
savings_pct  = (current − gp3) / current × 100
```

When the recommendation is pure baseline (`null`/`null`), `bill_iops` /
`bill_tp` equal the applicable included baseline (no extra IOPS/throughput
charges).

Override rates via script flags (`--rate-gp3-gb`, `--rate-piops`, …) when your
region differs. Cross-check with the
[AWS Pricing Calculator](https://calculator.aws/).

## Step 6 — Decision Matrix

| Condition | Verdict |
|-----------|---------|
| `need_iops` &gt; gp3 max (64K striped / 80K SQL Server) | **STAY on io2** |
| p99 latency &lt; 1 ms **and** confirmed hard sub-ms SLA | **STAY on io2** (manual; script only warns on sub-ms latency) |
| Dedicated Log Volume in use | **BLOCKER** (DLV = io1/io2 only) |
| Instance class EBS cap &lt; provisioned IOPS | Note: realized IOPS already below provisioned |
| Storage &lt; stripe threshold, needs &gt; 3K/125 | **CONDITIONAL**: grow storage or STAY |
| Savings ≥ 10% | **MIGRATE** |
| Savings &lt; 10% | **OPTIONAL** (standardize fleet) |

## Worked Example

**Current:** PostgreSQL, io2, 20,000 IOPS, 500 GiB, Multi-AZ, us-east-1.

**Observed (14-day):** p99 TotalIOPS = 7,200; peak throughput well under 500 MiB/s;
latencies ~1 ms (not a hard sub-ms SLA).

**Sizing:**

```
need_iops = 7200 × 1.2 = 8640
need_tp   ≤ 500
storage   = 500 GiB ≥ 400     → striped gp3; included baseline 12K / 500
8640 ≤ 12000 and need_tp ≤ 500 → recommend baseline (null / null)
```

**Cost (us-east-1 reference rates, Multi-AZ ×2):**

```
io2  = 500×0.125×2 + 20000×0.10×2 = 125 + 4000 = $4,125.00/mo
gp3  = 500×0.115×2 + 0 + 0 = $115.00/mo   # baseline included; no extra IOPS/TP
savings = (4125 − 115) / 4125 ≈ 97% ($4,010/mo)
```

**Verdict:** **MIGRATE** — demand fits under the included striped baseline, and
savings ≫ 10%.

> Format note: the formulas above and the script’s arithmetic are authoritative.

## Migration Execution

After a **MIGRATE** (or accepted **CONDITIONAL**) verdict, set root-stack
variables (see `variables.tf` / [storage-guide.md](./storage-guide.md)):

```hcl
db_instance_storage_type       = "gp3"
db_instance_iops               = null   # striped baseline (12K / 500) for this size
db_instance_storage_throughput = null
```

Apply with your usual `just plan` / `just apply` workflow. Storage type changes
are typically applied in the maintenance window unless
`db_apply_immediately = true` (brief impact). Details and downtime notes:
[storage-guide.md](./storage-guide.md).

## Post-Migration Validation

Re-check for at least **7 days** after cutover:

| Check | Expectation |
|-------|-------------|
| `DiskQueueDepth` | Not rising vs pre-migration under similar load |
| `ReadLatency` / `WriteLatency` p99 | Within app SLA vs new gp3 ceiling |
| p99 TotalIOPS | Comfortably under provisioned gp3 IOPS |
| `BurstBalance` | **Not applicable to gp3** — do not use it as a health signal for gp3 (the general [storage-guide.md](./storage-guide.md) still mentions burst for gp2/gp3 in places; for **gp3** post-PIOPS migrations, ignore `BurstBalance` and watch IOPS/throughput/latency/queue depth instead) |

## FAQ / Troubleshooting

**Stopped instance**  
`DBInstanceStatus` is `stopped`, or metrics are empty → flag as a **decommission**
candidate rather than a migration candidate.

**Empty or near-zero metrics**  
Usually stopped or very low traffic. Do not size from noise; either leave on
cheap PIOPS briefly, migrate to baseline gp3 for fleet standards, or delete.

**io1 with need &gt; gp3 max**  
gp3 max is **64K** IOPS (striped non–SQL Server) or **80K** (SQL Server). Stay on
**io2** (or reduce demand).

**Sub-ms latency**  
p99 read/write latency &lt; 1 ms is a **signal**, not an automatic stay. Confirm with
the app owner whether a hard sub-ms SLA exists before keeping PIOPS.

**Instance class EBS ceiling**  
EC2/RDS instance classes have network and EBS bandwidth caps. If the class
ceiling is below provisioned IOPS, realized performance was already capped —
gp3 should be sized to **observed** demand, not the old provisioned number.

**Dedicated Log Volume (DLV)**  
DLV requires io1/io2. **Cannot migrate** to gp3 while DLV is enabled — stay on
PIOPS or redesign without DLV first.

**Script exits with code 3**  
Storage type is not `io1`/`io2` — this assessment is only for PIOPS→gp3.

## References

- [Amazon RDS DB instance storage](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html)
- [Amazon RDS for gp3](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html#gp3-storage)
- [Modifying an Amazon RDS DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.DBInstance.Modifying.html)
- [CloudWatch metrics for Amazon RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/monitoring-cloudwatch.html)
- [AWS Pricing Calculator](https://calculator.aws/)
- [Storage Guide (this repo)](./storage-guide.md)
- [Measurement script](../scripts/measure-rds-storage.sh)

## License

MIT
