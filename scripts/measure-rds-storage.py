#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "boto3>=1.34",
# ]
# ///
"""Size equivalent RDS storage Terraform settings from CloudWatch demand.

Directions: io1/io2 → gp3, or gp3 → io2. Cost delta is informational.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any

import boto3
from botocore.exceptions import BotoCoreError, ClientError

SCRIPT_NAME = "measure-rds-storage.py"

# us-east-1 reference rates (informational cost only)
RATE_GP3_GB = 0.115
RATE_GP3_IOPS = 0.02
RATE_GP3_TP = 0.08
RATE_PIOPS_GB = 0.125
RATE_PIOPS = 0.10

IO2_MIN_IOPS = 1000
IO2_MAX_IOPS = 256000


def log(msg: str) -> None:
    print(f"[{SCRIPT_NAME}] {msg}", file=sys.stderr)


def die(msg: str, code: int) -> None:
    print(f"Error: {msg}", file=sys.stderr)
    raise SystemExit(code)


def is_sqlserver(engine: str) -> bool:
    return engine.startswith("sqlserver-")


def is_oracle(engine: str) -> bool:
    return engine in {
        "oracle-ee",
        "oracle-se2",
        "oracle-ee-cdb",
        "oracle-se2-cdb",
    }


def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def ceil_int(v: float) -> int:
    if v == int(v):
        return int(v)
    return int(v) + 1


def round_iops(v: float) -> int:
    if v <= 0:
        return 0
    return int((v + 99) // 100) * 100


def nearest_rank_percentile(sorted_vals: list[float], pct: float) -> float | None:
    n = len(sorted_vals)
    if n == 0:
        return None
    rank = math.ceil((pct / 100.0) * n)
    rank = max(1, min(n, rank))
    return sorted_vals[rank - 1]


def series_stats(values: list[float]) -> dict[str, float | None]:
    if not values:
        return {"avg": None, "p99": None, "max": None}
    s = sorted(values)
    return {
        "avg": sum(s) / len(s),
        "p99": nearest_rank_percentile(s, 99),
        "max": s[-1],
    }


@dataclass
class SizingResult:
    target: str
    rec_iops: int | None
    rec_tp: int | None
    bill_base_iops: int = 3000
    bill_base_tp: int = 125
    gp3_iops_bill: int | None = None
    gp3_tp_bill: int | None = None
    io2_iops: int | None = None
    needs_growth: bool = False
    over_max: bool = False
    dlv_blocker: bool = False
    recommendation_ok: bool = True
    stripe_threshold: int = 400
    gp3_max_iops: int = 64000
    notes: list[str] = field(default_factory=list)


def resolve_region(cli_region: str | None) -> str:
    if cli_region:
        return cli_region
    return os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "us-east-1"


def build_metric_queries(db_id: str, period: int) -> list[dict[str, Any]]:
    names = [
        "ReadIOPS",
        "WriteIOPS",
        "ReadLatency",
        "WriteLatency",
        "ReadThroughput",
        "WriteThroughput",
        "DiskQueueDepth",
        "CPUUtilization",
        "FreeableMemory",
        "CPUCreditBalance",
    ]
    queries: list[dict[str, Any]] = []
    for name in names:
        qid = name.lower()
        queries.append(
            {
                "Id": qid,
                "MetricStat": {
                    "Metric": {
                        "Namespace": "AWS/RDS",
                        "MetricName": name,
                        "Dimensions": [{"Name": "DBInstanceIdentifier", "Value": db_id}],
                    },
                    "Period": period,
                    "Stat": "Average",
                },
                "ReturnData": True,
            }
        )
    queries.append(
        {
            "Id": "total_iops",
            "Expression": "readiops + writeiops",
            "Label": "TotalIOPS",
            "ReturnData": True,
        }
    )
    queries.append(
        {
            "Id": "total_tp",
            "Expression": "readthroughput + writethroughput",
            "Label": "TotalThroughput",
            "ReturnData": True,
        }
    )
    return queries


def fetch_metric_values(
    cw: Any,
    db_id: str,
    start: datetime,
    end: datetime,
    period: int,
) -> dict[str, list[float]]:
    queries = build_metric_queries(db_id, period)
    by_id: dict[str, list[float]] = {q["Id"]: [] for q in queries}
    next_token: str | None = None
    while True:
        kwargs: dict[str, Any] = {
            "StartTime": start,
            "EndTime": end,
            "MetricDataQueries": queries,
        }
        if next_token:
            kwargs["NextToken"] = next_token
        resp = cw.get_metric_data(**kwargs)
        for result in resp.get("MetricDataResults", []):
            rid = result["Id"]
            by_id.setdefault(rid, []).extend(float(v) for v in result.get("Values", []))
        next_token = resp.get("NextToken")
        if not next_token:
            break
    return by_id


def size_to_gp3(
    *,
    engine: str,
    allocated: int,
    need_iops: float,
    need_tp: float,
    dlv: bool,
) -> SizingResult:
    stripe = 200 if is_oracle(engine) else 400
    result = SizingResult(target="gp3", rec_iops=None, rec_tp=None, stripe_threshold=stripe)

    if dlv:
        result.dlv_blocker = True
        result.recommendation_ok = False
        result.notes.append(
            "BLOCKER: Dedicated Log Volume is enabled — cannot use gp3 while DLV is on"
        )
        return result

    if is_sqlserver(engine):
        base_iops, base_tp = 3000, 125
        max_iops, max_tp = 80000, 2000
        result.bill_base_iops, result.bill_base_tp = base_iops, base_tp
        result.gp3_max_iops = max_iops
        if need_iops <= base_iops and need_tp <= base_tp:
            return result
        iops = clamp(need_iops, base_iops, max_iops)
        tp = clamp(need_tp, base_tp, max_tp)
        iops = max(iops, tp * 4)
        iops = clamp(iops, base_iops, max_iops)
        iops = round_iops(iops)
        if iops > max_iops:
            iops = max_iops
        tp = ceil_int(tp)
        if need_iops > max_iops:
            result.over_max = True
            result.recommendation_ok = False
        result.rec_iops = int(iops)
        result.rec_tp = int(tp)
        result.gp3_iops_bill = result.rec_iops
        result.gp3_tp_bill = result.rec_tp
        return result

    if allocated < stripe:
        result.bill_base_iops, result.bill_base_tp = 3000, 125
        if need_iops <= 3000 and need_tp <= 125:
            return result
        result.needs_growth = True
        result.recommendation_ok = False
        result.notes.append(
            f"Storage below stripe threshold or IOPS>size ratio — grow to ≥{stripe} GiB "
            "before tuning gp3, or stay on current type"
        )
        return result

    # Striped
    base_iops, base_tp = 12000, 500
    max_iops, max_tp = 64000, 4000
    result.bill_base_iops, result.bill_base_tp = base_iops, base_tp
    result.gp3_max_iops = max_iops
    if need_iops <= base_iops and need_tp <= base_tp:
        return result
    iops = clamp(need_iops, base_iops, max_iops)
    tp = clamp(need_tp, base_tp, max_tp)
    iops = max(iops, tp * 4)
    iops = clamp(iops, base_iops, max_iops)
    iops = round_iops(iops)
    if iops > max_iops:
        iops = max_iops
    tp = ceil_int(tp)
    if need_iops > max_iops:
        result.over_max = True
        result.recommendation_ok = False
    if iops > 500 * allocated:
        result.needs_growth = True
        result.notes.append(
            f"IOPS>size ratio — grow storage to ≥{stripe} GiB before tuning, or stay on current type"
        )
    result.rec_iops = int(iops)
    result.rec_tp = int(tp)
    result.gp3_iops_bill = result.rec_iops
    result.gp3_tp_bill = result.rec_tp
    return result


def size_to_io2(
    *,
    engine: str,
    allocated: int,
    need_iops: float,
) -> SizingResult:
    stripe = 200 if is_oracle(engine) else 400
    result = SizingResult(target="io2", rec_iops=None, rec_tp=None, stripe_threshold=stripe)

    if is_sqlserver(engine) or allocated < stripe:
        result.bill_base_iops, result.bill_base_tp = 3000, 125
    else:
        result.bill_base_iops, result.bill_base_tp = 12000, 500

    iops = round_iops(ceil_int(need_iops))
    if iops < IO2_MIN_IOPS:
        iops = IO2_MIN_IOPS
    if need_iops > IO2_MAX_IOPS:
        result.over_max = True
        result.recommendation_ok = False
        iops = IO2_MAX_IOPS
    if iops > IO2_MAX_IOPS:
        iops = IO2_MAX_IOPS
    result.rec_iops = iops
    result.rec_tp = None
    result.io2_iops = iops
    return result


def gp3_monthly_cost(
    gb: int,
    iops: int,
    tp: int,
    base_iops: int,
    base_tp: int,
    multi: int,
) -> float:
    iops_extra = max(0, iops - base_iops)
    tp_extra = max(0, tp - base_tp)
    return (gb * RATE_GP3_GB + iops_extra * RATE_GP3_IOPS + tp_extra * RATE_GP3_TP) * multi


def piops_monthly_cost(gb: int, iops: int, multi: int) -> float:
    return (gb * RATE_PIOPS_GB + iops * RATE_PIOPS) * multi


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog=SCRIPT_NAME,
        description=(
            "Size equivalent RDS storage Terraform settings from CloudWatch demand "
            "(io1/io2 → gp3, or gp3 → io2). Cost delta is informational."
        ),
    )
    p.add_argument("-i", "--db-instance", required=True, help="RDS DB instance identifier")
    p.add_argument("-r", "--region", default=None, help="AWS region")
    p.add_argument("-p", "--profile", default=None, help="AWS CLI/boto3 profile")
    p.add_argument("-d", "--days", type=int, default=14, help="CloudWatch lookback days (default 14)")
    p.add_argument(
        "-t",
        "--target",
        choices=("gp3", "io2"),
        default=None,
        help="Destination storage type (default: auto)",
    )
    p.add_argument(
        "-f",
        "--format",
        choices=("table", "json", "markdown"),
        default="table",
        help="Output format (default: table)",
    )
    p.add_argument("--headroom", type=float, default=1.2, help="Demand headroom multiplier (default 1.2)")
    args = p.parse_args(argv)
    if args.days < 1:
        die("--days must be a positive integer", 1)
    if args.headroom <= 0:
        die("--headroom must be positive", 1)
    return args


def fmt_num(v: float | None, places: int = 0) -> str:
    if v is None:
        return "n/a"
    if places == 0:
        return str(int(round(v)))
    return f"{v:.{places}f}"


def emit_table(ctx: dict[str, Any]) -> None:
    notes = ctx["notes"] or ["(none)"]
    note_lines = "\n".join(f"  - {n}" for n in notes)
    tf = ctx["tf_block"]
    print(
        f"""=== RDS Storage Type Sizing ===
Instance: {ctx['instance']} | Engine: {ctx['engine']} | Region: {ctx['region']}
Direction: {ctx['storage_type']} → {ctx['target']}

Current ({ctx['storage_type']}):
  Storage: {ctx['allocated']} GiB | IOPS: {ctx['current_iops_disp']} | Throughput: {ctx['current_tp_disp']}
  Multi-AZ: {ctx['multi_az_label']} | Instance class: {ctx['instance_class']} | Status: {ctx['status']}
  Estimated monthly cost: ${ctx['current_cost']:.2f}

Observed Metrics ({ctx['days']}-day lookback, period {ctx['period']}s):
  p99 ReadIOPS:     {fmt_num(ctx['riops_p99'])}
  p99 WriteIOPS:    {fmt_num(ctx['wiops_p99'])}
  p99 TotalIOPS:    {fmt_num(ctx['tiops_p99'])}
  p99 ReadLatency:  {fmt_num(ctx['rlat_p99_ms'], 2)} ms
  p99 WriteLatency: {fmt_num(ctx['wlat_p99_ms'], 2)} ms
  Avg DiskQueueDepth: {fmt_num(ctx['dq_avg'], 2)}
  Peak Throughput:    {fmt_num(ctx['peak_tp_mib'], 1)} MiB/s
  Avg CPUUtilization: {fmt_num(ctx['cpu_avg'], 1)}% (max {fmt_num(ctx['cpu_max'], 1)}%)
  Demand (headroom {ctx['headroom']}): need_iops={fmt_num(ctx['need_iops'])} need_tp={fmt_num(ctx['need_tp'], 1)} MiB/s

Recommended Terraform ({ctx['target']}):
{tf}

Estimated recommended monthly cost: ${ctx['rec_cost']:.2f}
Cost delta (current − recommended): {ctx['cost_delta_pct']:.2f}% (${ctx['cost_delta']:.2f}/mo)
  (positive = recommended is cheaper)

Notes:
{note_lines}
"""
    )


def emit_markdown(ctx: dict[str, Any]) -> None:
    notes = ctx["notes"] or ["(none)"]
    note_lines = "\n".join(f"- {n}" for n in notes)
    print(
        f"""# RDS Storage Type Sizing

| Field | Value |
|-------|-------|
| Instance | `{ctx['instance']}` |
| Engine | `{ctx['engine']}` |
| Region | `{ctx['region']}` |
| Direction | `{ctx['storage_type']}` → `{ctx['target']}` |
| Current cost | ${ctx['current_cost']:.2f}/mo |
| p99 TotalIOPS | {fmt_num(ctx['tiops_p99'])} |
| Recommended IOPS | {ctx['rec_iops'] if ctx['rec_iops'] is not None else 'null'} |
| Recommended throughput | {ctx['rec_tp'] if ctx['rec_tp'] is not None else 'null'} |
| Recommended cost | ${ctx['rec_cost']:.2f}/mo |
| Cost delta | {ctx['cost_delta_pct']:.2f}% (${ctx['cost_delta']:.2f}/mo) |

```hcl
{ctx['tf_hcl']}
```

Notes:
{note_lines}
"""
    )


def emit_json(ctx: dict[str, Any]) -> None:
    payload = {
        "instance": ctx["instance"],
        "engine": ctx["engine"],
        "region": ctx["region"],
        "direction": {"from": ctx["storage_type"], "to": ctx["target"]},
        "current": {
            "storage_type": ctx["storage_type"],
            "allocated_storage": ctx["allocated"],
            "iops": ctx["prov_iops"],
            "multi_az": ctx["multi_az"],
            "instance_class": ctx["instance_class"],
            "status": ctx["status"],
            "dedicated_log_volume": ctx["dlv"],
            "monthly_cost": ctx["current_cost"],
        },
        "metrics": {
            "lookback_days": ctx["days"],
            "period_seconds": ctx["period"],
            "p99_read_iops": ctx["riops_p99"],
            "p99_write_iops": ctx["wiops_p99"],
            "p99_total_iops": ctx["tiops_p99"],
            "p99_read_latency_ms": ctx["rlat_p99_ms"],
            "p99_write_latency_ms": ctx["wlat_p99_ms"],
            "avg_disk_queue_depth": ctx["dq_avg"],
            "peak_throughput_mib_s": ctx["peak_tp_mib"],
            "avg_cpu_utilization": ctx["cpu_avg"],
            "max_cpu_utilization": ctx["cpu_max"],
            "empty_metrics": ctx["empty_metrics"],
        },
        "sizing": {
            "need_iops": ctx["need_iops"],
            "need_throughput_mib_s": ctx["need_tp"],
            "recommendation_ok": ctx["recommendation_ok"],
            "db_instance_storage_type": ctx["target"],
            "db_instance_iops": ctx["rec_iops"],
            "db_instance_storage_throughput": ctx["rec_tp"],
        },
        "cost": {
            "current_monthly": ctx["current_cost"],
            "recommended_monthly": ctx["rec_cost"],
            "delta_monthly": ctx["cost_delta"],
            "delta_pct": ctx["cost_delta_pct"],
        },
        "notes": ctx["notes"],
    }
    print(json.dumps(payload, indent=2))


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(argv)
    except SystemExit as e:
        return int(e.code) if isinstance(e.code, int) else 1

    region = resolve_region(args.region)
    period = 60 if args.days <= 3 else 300

    session_kwargs: dict[str, Any] = {"region_name": region}
    if args.profile:
        session_kwargs["profile_name"] = args.profile

    log(f"Region: {region}" + (f" (profile {args.profile})" if args.profile else ""))
    log(f"Describing DB instance: {args.db_instance}")

    try:
        session = boto3.Session(**session_kwargs)
        rds = session.client("rds")
        cw = session.client("cloudwatch")
        desc = rds.describe_db_instances(DBInstanceIdentifier=args.db_instance)
    except (ClientError, BotoCoreError) as e:
        die(f"AWS error describing instance: {e}", 2)

    instances = desc.get("DBInstances") or []
    if not instances:
        die(f"DB instance not found: {args.db_instance} (check --region)", 2)

    inst = instances[0]
    engine = inst["Engine"]
    storage_type = inst["StorageType"]
    allocated = int(inst["AllocatedStorage"])
    prov_iops = int(inst.get("Iops") or 0)
    storage_tp = int(inst.get("StorageThroughput") or 0)
    multi_az = bool(inst.get("MultiAZ"))
    instance_class = inst["DBInstanceClass"]
    status = inst["DBInstanceStatus"]
    dlv = bool(inst.get("DedicatedLogVolume") or False)

    if storage_type in ("io1", "io2"):
        default_target = "gp3"
    elif storage_type == "gp3":
        default_target = "io2"
    else:
        die(f"Storage type '{storage_type}' is unsupported; only io1, io2, or gp3", 3)

    target = args.target or default_target
    if target == storage_type:
        die(f"Target '{target}' matches current storage type; nothing to size", 3)
    if storage_type == "gp3" and target != "io2":
        die("From gp3, only --target io2 is supported", 3)
    if storage_type in ("io1", "io2") and target != "gp3":
        die("From io1/io2, only --target gp3 is supported", 3)

    log(f"Direction: {storage_type} → {target}")
    if status == "stopped":
        log("Warning: instance status is 'stopped' — metrics may be empty.")

    end = datetime.now(timezone.utc)
    start = end - timedelta(days=args.days)
    log(f"Fetching CloudWatch metrics (--days {args.days}, period {period}s)…")

    try:
        series = fetch_metric_values(cw, args.db_instance, start, end, period)
    except (ClientError, BotoCoreError) as e:
        die(f"AWS error fetching metrics: {e}", 2)

    log("Metrics received; computing stats…")

    def st(name: str) -> dict[str, float | None]:
        return series_stats(series.get(name, []))

    ri = st("readiops")
    wi = st("writeiops")
    ti = st("total_iops")
    rl = st("readlatency")
    wl = st("writelatency")
    tp = st("total_tp")
    dq = st("diskqueuedepth")
    cpu = st("cpuutilization")

    empty_metrics = ti["p99"] is None
    if empty_metrics:
        log("Warning: no CloudWatch IOPS datapoints in the lookback window.")

    def sec_to_ms(v: float | None) -> float | None:
        return None if v is None else v * 1000.0

    def bytes_to_mib(v: float | None) -> float | None:
        return None if v is None else v / 1048576.0

    rlat_ms = sec_to_ms(rl["p99"])
    wlat_ms = sec_to_ms(wl["p99"])
    ttp_p99_mib = bytes_to_mib(tp["p99"])
    ttp_max_mib = bytes_to_mib(tp["max"])
    peak_tp = ttp_max_mib if ttp_max_mib is not None else ttp_p99_mib

    p99_iops = ti["p99"] or 0.0
    p99_tp = ttp_p99_mib or 0.0
    need_iops = p99_iops * args.headroom
    need_tp = p99_tp * args.headroom

    log(
        f"Sizing {target} from demand "
        f"(need_iops≈{ceil_int(need_iops)}, need_tp≈{need_tp:.1f} MiB/s)…"
    )

    if target == "gp3":
        sizing = size_to_gp3(
            engine=engine,
            allocated=allocated,
            need_iops=need_iops,
            need_tp=need_tp,
            dlv=dlv,
        )
    else:
        sizing = size_to_io2(engine=engine, allocated=allocated, need_iops=need_iops)

    multi = 2 if multi_az else 1

    # Current cost
    if storage_type == "gp3":
        cur_iops = prov_iops if prov_iops > 0 else sizing.bill_base_iops
        cur_tp = storage_tp if storage_tp > 0 else sizing.bill_base_tp
        current_cost = gp3_monthly_cost(
            allocated, cur_iops, cur_tp, sizing.bill_base_iops, sizing.bill_base_tp, multi
        )
    else:
        current_cost = piops_monthly_cost(allocated, prov_iops, multi)

    # Recommended cost
    if target == "gp3":
        bill_iops = sizing.gp3_iops_bill or sizing.bill_base_iops
        bill_tp = sizing.gp3_tp_bill or sizing.bill_base_tp
        if sizing.needs_growth and sizing.gp3_iops_bill is None:
            bill_iops, bill_tp = sizing.bill_base_iops, sizing.bill_base_tp
        rec_cost = gp3_monthly_cost(
            allocated, bill_iops, bill_tp, sizing.bill_base_iops, sizing.bill_base_tp, multi
        )
    else:
        bill_io2 = sizing.io2_iops or IO2_MIN_IOPS
        rec_cost = piops_monthly_cost(allocated, bill_io2, multi)

    cost_delta = current_cost - rec_cost
    cost_delta_pct = (cost_delta / current_cost * 100.0) if current_cost > 0 else 0.0

    notes = list(sizing.notes)
    if status == "stopped" or empty_metrics:
        notes.append("Empty or stopped metrics — verify traffic before applying recommended settings")
    if sizing.over_max:
        if target == "gp3":
            notes.append(
                f"need_iops ({need_iops:.0f}) exceeds gp3 max ({sizing.gp3_max_iops}) — gp3 may not meet demand"
            )
        else:
            notes.append(
                f"need_iops ({need_iops:.0f}) exceeds io2 methodology max ({IO2_MAX_IOPS})"
            )
    if rlat_ms is not None and wlat_ms is not None and rlat_ms < 1.0 and wlat_ms < 1.0:
        notes.append(
            "p99 latency < 1 ms — confirm with the app owner whether a hard sub-ms SLA applies"
        )
    if dq["avg"] is not None:
        ref = prov_iops if storage_type != "gp3" and prov_iops > 0 else max(1, ceil_int(need_iops))
        thresh = 10 * (ref / 10000)
        if dq["avg"] > thresh:
            notes.append("DiskQueueDepth suggests I/O pressure — do not undersize the destination")

    # Terraform snippet
    if sizing.dlv_blocker:
        tf_block = "  # No gp3 recommendation while Dedicated Log Volume is enabled"
        tf_hcl = "# No gp3 recommendation while Dedicated Log Volume is enabled"
    else:
        iops_line = "null" if sizing.rec_iops is None else str(sizing.rec_iops)
        tp_line = "null" if sizing.rec_tp is None else str(sizing.rec_tp)
        comment = ""
        if sizing.needs_growth and target == "gp3" and sizing.rec_iops is None:
            comment = (
                f"  # Grow allocated storage to ≥ {sizing.stripe_threshold} GiB "
                f"before tuning gp3, or keep {storage_type}\n"
            )
        tf_block = (
            f"{comment}"
            f'  db_instance_storage_type       = "{target}"\n'
            f"  db_instance_iops               = {iops_line}\n"
            f"  db_instance_storage_throughput = {tp_line}"
        )
        tf_hcl = (
            f'db_instance_storage_type       = "{target}"\n'
            f"db_instance_iops               = {iops_line}\n"
            f"db_instance_storage_throughput = {tp_line}"
        )

    if storage_type == "gp3":
        current_iops_disp = "baseline" if prov_iops == 0 else str(prov_iops)
        current_tp_disp = "baseline" if storage_tp == 0 else str(storage_tp)
    else:
        current_iops_disp = str(prov_iops)
        current_tp_disp = "n/a"

    ctx = {
        "instance": args.db_instance,
        "engine": engine,
        "region": region,
        "storage_type": storage_type,
        "target": target,
        "allocated": allocated,
        "prov_iops": prov_iops,
        "current_iops_disp": current_iops_disp,
        "current_tp_disp": current_tp_disp,
        "multi_az": multi_az,
        "multi_az_label": "Yes" if multi_az else "No",
        "instance_class": instance_class,
        "status": status,
        "dlv": dlv,
        "days": args.days,
        "period": period,
        "headroom": args.headroom,
        "riops_p99": ri["p99"],
        "wiops_p99": wi["p99"],
        "tiops_p99": ti["p99"],
        "rlat_p99_ms": rlat_ms,
        "wlat_p99_ms": wlat_ms,
        "dq_avg": dq["avg"],
        "peak_tp_mib": peak_tp,
        "cpu_avg": cpu["avg"],
        "cpu_max": cpu["max"],
        "need_iops": need_iops,
        "need_tp": need_tp,
        "empty_metrics": empty_metrics,
        "rec_iops": sizing.rec_iops,
        "rec_tp": sizing.rec_tp,
        "recommendation_ok": sizing.recommendation_ok,
        "current_cost": current_cost,
        "rec_cost": rec_cost,
        "cost_delta": cost_delta,
        "cost_delta_pct": cost_delta_pct,
        "notes": notes,
        "tf_block": tf_block,
        "tf_hcl": tf_hcl,
    }

    log("Done.")
    if args.format == "table":
        emit_table(ctx)
    elif args.format == "markdown":
        emit_markdown(ctx)
    else:
        emit_json(ctx)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
