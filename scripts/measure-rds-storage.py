#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "boto3>=1.34",
# ]
# ///
"""Size equivalent RDS storage Terraform settings from CloudWatch demand.

Directions: io1/io2 → gp3, or gp3 → io2.
Default sizing uses Maximum Read/Write IOPS and throughput (console/Q/Rovo-aligned),
with instance-class EBS caps and regional Price List rates when available.
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

# Fallback us-east-1 reference rates if Price List API fails
FALLBACK_RATE_GP3_GB = 0.115
FALLBACK_RATE_GP3_IOPS = 0.02
FALLBACK_RATE_GP3_TP = 0.08
FALLBACK_RATE_PIOPS_GB = 0.125
FALLBACK_RATE_PIOPS = 0.10

IO2_MIN_IOPS = 1000
IO2_MAX_IOPS = 256000

# EBS-optimized limits for common RDS classes (max / baseline IOPS and MiB/s).
# Source: EC2 EBS-optimized instance specs (RDS db.* maps to same family).
INSTANCE_CLASS_EBS: dict[str, dict[str, float]] = {
    "db.m5.large": {"max_iops": 18750, "baseline_iops": 3000, "max_tp_mib": 593.75, "baseline_tp_mib": 71.88},
    "db.m5.xlarge": {"max_iops": 18750, "baseline_iops": 6000, "max_tp_mib": 593.75, "baseline_tp_mib": 143.75},
    "db.m5.2xlarge": {"max_iops": 18750, "baseline_iops": 12000, "max_tp_mib": 593.75, "baseline_tp_mib": 287.5},
    "db.m5.4xlarge": {"max_iops": 18750, "baseline_iops": 18750, "max_tp_mib": 593.75, "baseline_tp_mib": 593.75},
    "db.m5.8xlarge": {"max_iops": 30000, "baseline_iops": 30000, "max_tp_mib": 850.0, "baseline_tp_mib": 850.0},
    "db.m5.12xlarge": {"max_iops": 40000, "baseline_iops": 40000, "max_tp_mib": 1187.5, "baseline_tp_mib": 1187.5},
    "db.m6i.large": {"max_iops": 20000, "baseline_iops": 3000, "max_tp_mib": 625.0, "baseline_tp_mib": 78.13},
    "db.m6i.xlarge": {"max_iops": 20000, "baseline_iops": 6000, "max_tp_mib": 625.0, "baseline_tp_mib": 156.25},
    "db.m6i.2xlarge": {"max_iops": 20000, "baseline_iops": 12000, "max_tp_mib": 625.0, "baseline_tp_mib": 312.5},
    "db.m6i.4xlarge": {"max_iops": 20000, "baseline_iops": 20000, "max_tp_mib": 625.0, "baseline_tp_mib": 625.0},
    "db.r5.large": {"max_iops": 18750, "baseline_iops": 3000, "max_tp_mib": 593.75, "baseline_tp_mib": 71.88},
    "db.r5.xlarge": {"max_iops": 18750, "baseline_iops": 6000, "max_tp_mib": 593.75, "baseline_tp_mib": 143.75},
    "db.r5.2xlarge": {"max_iops": 18750, "baseline_iops": 12000, "max_tp_mib": 593.75, "baseline_tp_mib": 287.5},
    "db.r5.4xlarge": {"max_iops": 18750, "baseline_iops": 18750, "max_tp_mib": 593.75, "baseline_tp_mib": 593.75},
    "db.r6i.large": {"max_iops": 20000, "baseline_iops": 3000, "max_tp_mib": 625.0, "baseline_tp_mib": 78.13},
    "db.r6i.xlarge": {"max_iops": 20000, "baseline_iops": 6000, "max_tp_mib": 625.0, "baseline_tp_mib": 156.25},
    "db.r6i.2xlarge": {"max_iops": 20000, "baseline_iops": 12000, "max_tp_mib": 625.0, "baseline_tp_mib": 312.5},
    "db.r6i.4xlarge": {"max_iops": 20000, "baseline_iops": 20000, "max_tp_mib": 625.0, "baseline_tp_mib": 625.0},
}


def log(msg: str) -> None:
    print(f"→ {msg}", file=sys.stderr)


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


def lookup_instance_class(instance_class: str) -> dict[str, float] | None:
    return INSTANCE_CLASS_EBS.get(instance_class)


@dataclass
class Rates:
    gp3_gb: float = FALLBACK_RATE_GP3_GB
    gp3_iops: float = FALLBACK_RATE_GP3_IOPS
    gp3_tp: float = FALLBACK_RATE_GP3_TP
    piops_gb: float = FALLBACK_RATE_PIOPS_GB
    piops: float = FALLBACK_RATE_PIOPS
    source: str = "fallback us-east-1 reference constants"


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


def _metric_stat_query(qid: str, name: str, db_id: str, period: int, stat: str) -> dict[str, Any]:
    return {
        "Id": qid,
        "MetricStat": {
            "Metric": {
                "Namespace": "AWS/RDS",
                "MetricName": name,
                "Dimensions": [{"Name": "DBInstanceIdentifier", "Value": db_id}],
            },
            "Period": period,
            "Stat": stat,
        },
        "ReturnData": True,
    }


def build_metric_queries(db_id: str, period: int) -> list[dict[str, Any]]:
    queries: list[dict[str, Any]] = []
    # Average + Maximum for the four metrics used by console/Q/Rovo sizing
    for name in ("ReadIOPS", "WriteIOPS", "ReadThroughput", "WriteThroughput"):
        base = name.lower()
        queries.append(_metric_stat_query(f"{base}_avg", name, db_id, period, "Average"))
        queries.append(_metric_stat_query(f"{base}_max", name, db_id, period, "Maximum"))

    # Context metrics (Average only)
    for name in (
        "ReadLatency",
        "WriteLatency",
        "DiskQueueDepth",
        "CPUUtilization",
        "FreeableMemory",
        "CPUCreditBalance",
    ):
        queries.append(_metric_stat_query(name.lower(), name, db_id, period, "Average"))

    # Totals from Average series (for p99-of-averages display)
    queries.append(
        {
            "Id": "total_iops_avg",
            "Expression": "readiops_avg + writeiops_avg",
            "Label": "TotalIOPS_Avg",
            "ReturnData": True,
        }
    )
    queries.append(
        {
            "Id": "total_tp_avg",
            "Expression": "readthroughput_avg + writethroughput_avg",
            "Label": "TotalThroughput_Avg",
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
    # GetMetricData allows max 500 queries; we are well under.
    # Split into batches of 100 if needed for safety.
    by_id: dict[str, list[float]] = {}
    batch_size = 100
    for i in range(0, len(queries), batch_size):
        batch = queries[i : i + batch_size]
        next_token: str | None = None
        while True:
            kwargs: dict[str, Any] = {
                "StartTime": start,
                "EndTime": end,
                "MetricDataQueries": batch,
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


def fetch_regional_rates(session: Any, region: str) -> Rates:
    """Best-effort Price List rates for AmazonRDS in the instance region."""
    rates = Rates()
    try:
        # Price List Query API endpoints are regional but independent of product region.
        pricing = session.client("pricing", region_name="us-east-1")

        def first_usd_price(price_list: list[str]) -> float | None:
            for raw in price_list:
                try:
                    doc = json.loads(raw)
                    terms = doc.get("terms", {}).get("OnDemand", {})
                    for term in terms.values():
                        for dim in term.get("priceDimensions", {}).values():
                            usd = dim.get("pricePerUnit", {}).get("USD")
                            if usd is not None:
                                return float(usd)
                except (json.JSONDecodeError, TypeError, ValueError):
                    continue
            return None

        def query(filters: list[dict[str, str]]) -> float | None:
            resp = pricing.get_products(
                ServiceCode="AmazonRDS",
                Filters=[{"Type": "TERM_MATCH", **f} for f in filters],
                MaxResults=10,
            )
            return first_usd_price(resp.get("PriceList") or [])

        loc_filter = {"Field": "location", "Value": _region_to_location(region)}

        gp3_gb = query(
            [
                loc_filter,
                {"Field": "volumeType", "Value": "General Purpose-GP3"},
                {"Field": "productFamily", "Value": "Database Storage"},
            ]
        )
        # Broader fallbacks commonly used in price lists
        if gp3_gb is None:
            gp3_gb = query(
                [
                    loc_filter,
                    {"Field": "storageMedia", "Value": "SSD"},
                    {"Field": "volumeType", "Value": "General Purpose"},
                ]
            )

        piops_gb = query(
            [
                loc_filter,
                {"Field": "volumeType", "Value": "Provisioned IOPS"},
                {"Field": "productFamily", "Value": "Database Storage"},
            ]
        )

        # IOPS / throughput SKUs vary by attribute naming; keep fallbacks if missing
        if gp3_gb is not None:
            rates.gp3_gb = gp3_gb
        if piops_gb is not None:
            rates.piops_gb = piops_gb

        if gp3_gb is not None or piops_gb is not None:
            rates.source = f"AWS Price List API (partial) for {region}; IOPS/TP may use fallbacks"
            log(f"Pricing: loaded storage GB rates from Price List for {region}")
        else:
            log("Pricing: Price List returned no matching products; using fallback constants")
    except (ClientError, BotoCoreError, Exception) as e:  # noqa: BLE001
        log(f"Pricing: Price List unavailable ({e}); using fallback constants")
        rates.source = f"fallback constants (Price List error)"
    return rates


def _region_to_location(region: str) -> str:
    """Map region code to Price List 'location' attribute (common set)."""
    mapping = {
        "us-east-1": "US East (N. Virginia)",
        "us-east-2": "US East (Ohio)",
        "us-west-1": "US West (N. California)",
        "us-west-2": "US West (Oregon)",
        "eu-west-1": "EU (Ireland)",
        "eu-west-2": "EU (London)",
        "eu-central-1": "EU (Frankfurt)",
        "eu-north-1": "EU (Stockholm)",
        "ap-southeast-1": "Asia Pacific (Singapore)",
        "ap-southeast-2": "Asia Pacific (Sydney)",
        "ap-northeast-1": "Asia Pacific (Tokyo)",
        "sa-east-1": "South America (Sao Paulo)",
        "ca-central-1": "Canada (Central)",
    }
    return mapping.get(region, "US East (N. Virginia)")


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
        # Round throughput to a practical step (nearest 25)
        tp = int(math.ceil(tp / 25.0) * 25)
        tp = int(clamp(tp, base_tp, max_tp))
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
            f"Storage below stripe threshold — grow to ≥{stripe} GiB "
            "before tuning gp3, or stay on current type"
        )
        return result

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
            f"IOPS>size ratio — grow storage or stay on current type"
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


def apply_instance_class_caps(
    sizing: SizingResult,
    *,
    instance_class: str,
    need_iops: float,
    need_tp: float,
    prov_iops: int,
) -> None:
    limits = lookup_instance_class(instance_class)
    if limits is None:
        sizing.notes.append(
            f"No EBS limit table entry for {instance_class} — could not clamp to instance class"
        )
        return

    max_iops = int(limits["max_iops"])
    max_tp = float(limits["max_tp_mib"])
    base_iops = int(limits["baseline_iops"])
    base_tp = float(limits["baseline_tp_mib"])

    if need_iops > max_iops or need_tp > max_tp:
        sizing.notes.append(
            f"Peak demand exceeds {instance_class} EBS max "
            f"({max_iops} IOPS / {max_tp:.0f} MiB/s) — consider a larger instance class"
        )
    if prov_iops > max_iops:
        sizing.notes.append(
            f"Current provisioned IOPS ({prov_iops}) > {instance_class} max ({max_iops}) — "
            "realized performance was already class-capped"
        )

    if sizing.rec_iops is not None and sizing.rec_iops > max_iops:
        sizing.rec_iops = max_iops
        sizing.gp3_iops_bill = max_iops
        if sizing.io2_iops is not None:
            sizing.io2_iops = max_iops
        sizing.notes.append(f"Clamped recommended iops to {instance_class} max {max_iops}")

    if sizing.rec_tp is not None and sizing.rec_tp > max_tp:
        sizing.rec_tp = int(math.floor(max_tp))
        sizing.gp3_tp_bill = sizing.rec_tp
        sizing.notes.append(
            f"Clamped recommended storage_throughput to {instance_class} max {sizing.rec_tp} MiB/s"
        )


def gp3_monthly_cost(
    gb: int,
    iops: int,
    tp: int,
    base_iops: int,
    base_tp: int,
    multi: int,
    rates: Rates,
) -> float:
    iops_extra = max(0, iops - base_iops)
    tp_extra = max(0, tp - base_tp)
    return (
        gb * rates.gp3_gb + iops_extra * rates.gp3_iops + tp_extra * rates.gp3_tp
    ) * multi


def piops_monthly_cost(gb: int, iops: int, multi: int, rates: Rates) -> float:
    return (gb * rates.piops_gb + iops * rates.piops) * multi


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog=SCRIPT_NAME,
        description=(
            "Size equivalent RDS storage settings from CloudWatch demand "
            "(io1/io2 → gp3, or gp3 → io2). Default: Maximum peaks (console/Q-aligned)."
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
    p.add_argument(
        "--size-from",
        choices=("maximum", "p99-average"),
        default="maximum",
        help="Demand basis for sizing (default: maximum = console/Q/Rovo-aligned)",
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


def build_summary(ctx: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    target = ctx["target"]
    need_iops = ctx["need_iops"]
    need_tp = ctx["need_tp"]
    base_iops = ctx["baseline_iops"]
    base_tp = ctx["baseline_tp"]
    uses_baseline = ctx["uses_baseline"]
    size_from = ctx["size_from"]

    lines.append(
        f"Sized from {'Maximum peaks (Read+Write)' if size_from == 'maximum' else 'p99 of Averages'} "
        f"× headroom {ctx['headroom']}."
    )
    lines.append(
        f"Peak observed: max ReadIOPS={fmt_num(ctx['riops_max'])}, "
        f"max WriteIOPS={fmt_num(ctx['wiops_max'])}, "
        f"sum≈{fmt_num(ctx['peak_iops_sum'])}; "
        f"p99 avg TotalIOPS={fmt_num(ctx['tiops_p99'])}."
    )
    lines.append(
        f"Demand with headroom: need_iops≈{fmt_num(need_iops)}, "
        f"need_tp≈{fmt_num(need_tp, 1)} MiB/s."
    )

    cls = ctx.get("class_limits")
    if cls:
        lines.append(
            f"Instance class {ctx['instance_class']}: EBS baseline "
            f"{int(cls['baseline_iops'])} IOPS / {cls['baseline_tp_mib']:.0f} MiB/s, "
            f"max {int(cls['max_iops'])} IOPS / {cls['max_tp_mib']:.0f} MiB/s."
        )

    if target == "gp3":
        lines.append(
            f"Applicable included gp3 baseline for this engine/size: "
            f"{base_iops} IOPS / {base_tp} MiB/s."
        )
        if ctx["dlv_blocker"]:
            lines.append("No gp3 recommendation: Dedicated Log Volume blocks gp3.")
        elif ctx["needs_growth"] and uses_baseline and ctx["rec_iops"] is None:
            lines.append(
                f"Demand exceeds baseline-only volume (< stripe {ctx['stripe_threshold']} GiB); "
                "grow storage or keep current type before tuning gp3."
            )
        elif uses_baseline:
            lines.append(
                f"iops/storage_throughput = null means use the included baseline "
                f"({base_iops} IOPS / {base_tp} MiB/s) — demand fits under baseline."
            )
        else:
            lines.append(
                f"Provisioned above gp3 baseline: iops={ctx['rec_iops']}, "
                f"storage_throughput={ctx['rec_tp']} "
                f"(extras billed above {base_iops} IOPS / {base_tp} MiB/s)."
            )
    else:
        lines.append(
            f"Recommended io2 iops={ctx['rec_iops']} "
            f"(storage_throughput = null for io2)."
        )

    lines.append(f"Cost rates: {ctx['rates_source']}")
    return lines


def emit_table(ctx: dict[str, Any]) -> None:
    summary_lines = "\n".join(f"  - {s}" for s in ctx["summary"])
    notes = ctx["notes"]
    notes_block = ""
    if notes:
        # Class baseline annotation is informational — keep under Notes as planned
        note_lines = "\n".join(f"  - {n}" for n in notes)
        notes_block = f"\nNotes:\n{note_lines}\n"
    tf = ctx["tf_block"]
    print(
        f"""=== RDS Storage Type Sizing ===
Instance: {ctx['instance']} | Engine: {ctx['engine']} | Region: {ctx['region']}
Direction: {ctx['storage_type']} → {ctx['target']} | size-from: {ctx['size_from']}

Current ({ctx['storage_type']}):
  Storage: {ctx['allocated']} GiB | IOPS: {ctx['current_iops_disp']} | Throughput: {ctx['current_tp_disp']}
  Multi-AZ: {ctx['multi_az_label']} | Instance class: {ctx['instance_class']} | Status: {ctx['status']}
  Estimated monthly cost: ${ctx['current_cost']:.2f}

Observed Metrics ({ctx['days']}-day lookback, period {ctx['period']}s):
  Maximum ReadIOPS:     {fmt_num(ctx['riops_max'])}
  Maximum WriteIOPS:    {fmt_num(ctx['wiops_max'])}
  Peak IOPS (maxR+maxW): {fmt_num(ctx['peak_iops_sum'])}
  Maximum ReadThroughput:  {fmt_num(ctx['rtp_max_mib'], 1)} MiB/s
  Maximum WriteThroughput: {fmt_num(ctx['wtp_max_mib'], 1)} MiB/s
  Peak TP (maxR+maxW):     {fmt_num(ctx['peak_tp_sum_mib'], 1)} MiB/s
  p99 avg TotalIOPS:    {fmt_num(ctx['tiops_p99'])}
  p99 avg TotalTP:      {fmt_num(ctx['ttp_p99_mib'], 1)} MiB/s
  p99 ReadLatency:      {fmt_num(ctx['rlat_p99_ms'], 2)} ms
  p99 WriteLatency:     {fmt_num(ctx['wlat_p99_ms'], 2)} ms
  Avg DiskQueueDepth:   {fmt_num(ctx['dq_avg'], 2)}
  Demand (headroom {ctx['headroom']}): need_iops={fmt_num(ctx['need_iops'])} need_tp={fmt_num(ctx['need_tp'], 1)} MiB/s

Summary:
{summary_lines}

Recommended settings ({ctx['target']}):
{tf}

Estimated recommended monthly cost: ${ctx['rec_cost']:.2f}
Cost delta (current − recommended): {ctx['cost_delta_pct']:.2f}% (${ctx['cost_delta']:.2f}/mo)
  (positive = recommended is cheaper)
{notes_block}"""
    )


def emit_markdown(ctx: dict[str, Any]) -> None:
    summary_lines = "\n".join(f"- {s}" for s in ctx["summary"])
    notes = ctx["notes"]
    notes_block = ""
    if notes:
        note_lines = "\n".join(f"- {n}" for n in notes)
        notes_block = f"\n## Notes\n\n{note_lines}\n"
    print(
        f"""# RDS Storage Type Sizing

| Field | Value |
|-------|-------|
| Instance | `{ctx['instance']}` |
| Engine | `{ctx['engine']}` |
| Region | `{ctx['region']}` |
| Direction | `{ctx['storage_type']}` → `{ctx['target']}` |
| size-from | `{ctx['size_from']}` |
| Peak IOPS (maxR+maxW) | {fmt_num(ctx['peak_iops_sum'])} |
| Peak TP (maxR+maxW) | {fmt_num(ctx['peak_tp_sum_mib'], 1)} MiB/s |
| p99 avg TotalIOPS | {fmt_num(ctx['tiops_p99'])} |
| Recommended IOPS | {ctx['rec_iops'] if ctx['rec_iops'] is not None else 'null (baseline)'} |
| Recommended throughput | {ctx['rec_tp'] if ctx['rec_tp'] is not None else 'null (baseline)'} |
| Current cost | ${ctx['current_cost']:.2f}/mo |
| Recommended cost | ${ctx['rec_cost']:.2f}/mo |

## Summary

{summary_lines}

```hcl
{ctx['tf_hcl']}
```
{notes_block}"""
    )


def emit_json(ctx: dict[str, Any]) -> None:
    payload = {
        "instance": ctx["instance"],
        "engine": ctx["engine"],
        "region": ctx["region"],
        "direction": {"from": ctx["storage_type"], "to": ctx["target"]},
        "size_from": ctx["size_from"],
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
        "instance_class_ebs": ctx.get("class_limits"),
        "metrics": {
            "lookback_days": ctx["days"],
            "period_seconds": ctx["period"],
            "max_read_iops": ctx["riops_max"],
            "max_write_iops": ctx["wiops_max"],
            "peak_iops_sum": ctx["peak_iops_sum"],
            "max_read_throughput_mib_s": ctx["rtp_max_mib"],
            "max_write_throughput_mib_s": ctx["wtp_max_mib"],
            "peak_throughput_sum_mib_s": ctx["peak_tp_sum_mib"],
            "p99_avg_total_iops": ctx["tiops_p99"],
            "p99_avg_total_throughput_mib_s": ctx["ttp_p99_mib"],
            "p99_read_latency_ms": ctx["rlat_p99_ms"],
            "p99_write_latency_ms": ctx["wlat_p99_ms"],
            "avg_disk_queue_depth": ctx["dq_avg"],
            "empty_metrics": ctx["empty_metrics"],
        },
        "sizing": {
            "need_iops": ctx["need_iops"],
            "need_throughput_mib_s": ctx["need_tp"],
            "recommendation_ok": ctx["recommendation_ok"],
            "storage_type": ctx["target"],
            "iops": ctx["rec_iops"],
            "storage_throughput": ctx["rec_tp"],
            "baseline_iops": ctx["baseline_iops"],
            "baseline_throughput_mib_s": ctx["baseline_tp"],
            "uses_baseline": ctx["uses_baseline"],
        },
        "cost": {
            "current_monthly": ctx["current_cost"],
            "recommended_monthly": ctx["rec_cost"],
            "delta_monthly": ctx["cost_delta"],
            "delta_pct": ctx["cost_delta_pct"],
            "rates_source": ctx["rates_source"],
        },
        "summary": ctx["summary"],
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

    log(f"Direction: {storage_type} → {target} | size-from: {args.size_from}")
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
    log("Loading regional price list (best-effort)…")
    rates = fetch_regional_rates(session, region)

    def st(name: str) -> dict[str, float | None]:
        return series_stats(series.get(name, []))

    ri_avg = st("readiops_avg")
    wi_avg = st("writeiops_avg")
    ri_max = st("readiops_max")
    wi_max = st("writeiops_max")
    rtp_max = st("readthroughput_max")
    wtp_max = st("writethroughput_max")
    ti_avg = st("total_iops_avg")
    tp_avg = st("total_tp_avg")
    rl = st("readlatency")
    wl = st("writelatency")
    dq = st("diskqueuedepth")

    empty_metrics = (ri_max["max"] is None and wi_max["max"] is None and ti_avg["p99"] is None)
    if empty_metrics:
        log("Warning: no CloudWatch IOPS datapoints in the lookback window.")

    def sec_to_ms(v: float | None) -> float | None:
        return None if v is None else v * 1000.0

    def bytes_to_mib(v: float | None) -> float | None:
        return None if v is None else v / 1048576.0

    rlat_ms = sec_to_ms(rl["p99"])
    wlat_ms = sec_to_ms(wl["p99"])

    riops_max_v = ri_max["max"] or 0.0
    wiops_max_v = wi_max["max"] or 0.0
    peak_iops_sum = riops_max_v + wiops_max_v
    rtp_max_mib = bytes_to_mib(rtp_max["max"]) or 0.0
    wtp_max_mib = bytes_to_mib(wtp_max["max"]) or 0.0
    peak_tp_sum_mib = rtp_max_mib + wtp_max_mib

    ttp_p99_mib = bytes_to_mib(tp_avg["p99"]) or 0.0
    p99_iops = ti_avg["p99"] or 0.0

    if args.size_from == "maximum":
        need_iops = peak_iops_sum * args.headroom
        need_tp = peak_tp_sum_mib * args.headroom
    else:
        need_iops = p99_iops * args.headroom
        need_tp = ttp_p99_mib * args.headroom

    log(
        f"Sizing {target} from {args.size_from} "
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

    apply_instance_class_caps(
        sizing,
        instance_class=instance_class,
        need_iops=need_iops,
        need_tp=need_tp,
        prov_iops=prov_iops,
    )

    multi = 2 if multi_az else 1

    if storage_type == "gp3":
        cur_iops = prov_iops if prov_iops > 0 else sizing.bill_base_iops
        cur_tp = storage_tp if storage_tp > 0 else sizing.bill_base_tp
        current_cost = gp3_monthly_cost(
            allocated,
            cur_iops,
            cur_tp,
            sizing.bill_base_iops,
            sizing.bill_base_tp,
            multi,
            rates,
        )
    else:
        current_cost = piops_monthly_cost(allocated, prov_iops, multi, rates)

    if target == "gp3":
        bill_iops = sizing.gp3_iops_bill or sizing.bill_base_iops
        bill_tp = sizing.gp3_tp_bill or sizing.bill_base_tp
        if sizing.needs_growth and sizing.gp3_iops_bill is None:
            bill_iops, bill_tp = sizing.bill_base_iops, sizing.bill_base_tp
        rec_cost = gp3_monthly_cost(
            allocated,
            bill_iops,
            bill_tp,
            sizing.bill_base_iops,
            sizing.bill_base_tp,
            multi,
            rates,
        )
    else:
        bill_io2 = sizing.io2_iops or IO2_MIN_IOPS
        rec_cost = piops_monthly_cost(allocated, bill_io2, multi, rates)

    cost_delta = current_cost - rec_cost
    cost_delta_pct = (cost_delta / current_cost * 100.0) if current_cost > 0 else 0.0

    notes = list(sizing.notes)
    if status == "stopped" or empty_metrics:
        notes.append("Empty or stopped metrics — verify traffic before applying recommended settings")
    if sizing.over_max:
        if target == "gp3":
            notes.append(
                f"need_iops ({need_iops:.0f}) exceeds gp3 max ({sizing.gp3_max_iops})"
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

    uses_baseline = target == "gp3" and sizing.rec_iops is None and not sizing.dlv_blocker
    baseline_iops = sizing.bill_base_iops
    baseline_tp = sizing.bill_base_tp
    class_limits = lookup_instance_class(instance_class)

    if sizing.dlv_blocker:
        tf_block = "  # No gp3 recommendation while Dedicated Log Volume is enabled"
        tf_hcl = "# No gp3 recommendation while Dedicated Log Volume is enabled"
    else:
        if sizing.rec_iops is None and target == "gp3":
            iops_line = f"null  # included baseline: {baseline_iops} IOPS"
            tp_line = f"null  # included baseline: {baseline_tp} MiB/s"
        elif target == "io2":
            iops_line = str(sizing.rec_iops)
            tp_line = "null  # not used for io2"
        else:
            iops_line = str(sizing.rec_iops)
            tp_line = str(sizing.rec_tp)
        comment = ""
        if sizing.needs_growth and target == "gp3" and sizing.rec_iops is None:
            comment = (
                f"  # Grow allocated storage to ≥ {sizing.stripe_threshold} GiB "
                f"before tuning gp3, or keep {storage_type}\n"
            )
        tf_block = (
            f"{comment}"
            f'  storage_type       = "{target}"\n'
            f"  iops               = {iops_line}\n"
            f"  storage_throughput = {tp_line}"
        )
        tf_hcl = (
            f'storage_type       = "{target}"\n'
            f"iops               = {iops_line}\n"
            f"storage_throughput = {tp_line}"
        )

    if storage_type == "gp3":
        current_iops_disp = "baseline" if prov_iops == 0 else str(prov_iops)
        current_tp_disp = "baseline" if storage_tp == 0 else str(storage_tp)
    else:
        current_iops_disp = str(prov_iops)
        current_tp_disp = "n/a"

    ctx: dict[str, Any] = {
        "instance": args.db_instance,
        "engine": engine,
        "region": region,
        "storage_type": storage_type,
        "target": target,
        "size_from": args.size_from,
        "allocated": allocated,
        "prov_iops": prov_iops,
        "current_iops_disp": current_iops_disp,
        "current_tp_disp": current_tp_disp,
        "multi_az": multi_az,
        "multi_az_label": "Yes" if multi_az else "No",
        "instance_class": instance_class,
        "class_limits": class_limits,
        "status": status,
        "dlv": dlv,
        "dlv_blocker": sizing.dlv_blocker,
        "needs_growth": sizing.needs_growth,
        "stripe_threshold": sizing.stripe_threshold,
        "days": args.days,
        "period": period,
        "headroom": args.headroom,
        "riops_max": ri_max["max"],
        "wiops_max": wi_max["max"],
        "peak_iops_sum": peak_iops_sum,
        "rtp_max_mib": rtp_max_mib,
        "wtp_max_mib": wtp_max_mib,
        "peak_tp_sum_mib": peak_tp_sum_mib,
        "tiops_p99": ti_avg["p99"],
        "ttp_p99_mib": ttp_p99_mib,
        "rlat_p99_ms": rlat_ms,
        "wlat_p99_ms": wlat_ms,
        "dq_avg": dq["avg"],
        "need_iops": need_iops,
        "need_tp": need_tp,
        "empty_metrics": empty_metrics,
        "rec_iops": sizing.rec_iops,
        "rec_tp": sizing.rec_tp,
        "baseline_iops": baseline_iops,
        "baseline_tp": baseline_tp,
        "uses_baseline": uses_baseline,
        "recommendation_ok": sizing.recommendation_ok,
        "current_cost": current_cost,
        "rec_cost": rec_cost,
        "cost_delta": cost_delta,
        "cost_delta_pct": cost_delta_pct,
        "rates_source": rates.source,
        "notes": notes,
        "tf_block": tf_block,
        "tf_hcl": tf_hcl,
    }
    ctx["summary"] = build_summary(ctx)

    log("Done.")
    print("", file=sys.stderr)
    if args.format == "table":
        emit_table(ctx)
    elif args.format == "markdown":
        emit_markdown(ctx)
    else:
        emit_json(ctx)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
