#!/usr/bin/env bash
# measure-rds-storage.sh — Assess io1/io2 → gp3 migration candidacy for an RDS instance.
#
# Usage:
#   ./scripts/measure-rds-storage.sh --db-instance <id> [options]
#
# Exit codes:
#   0  ok
#   1  usage / argument error
#   2  AWS / dependency error
#   3  unsupported config (not io1/io2)
#
# Sample (table) output shape:
#   === RDS Storage Migration Assessment ===
#   Instance: my-db-prod | Engine: postgres | Region: us-east-1
#   ...
#   Decision: MIGRATE
#
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# Defaults
DB_INSTANCE=""
DAYS=14
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
PROFILE=""
HEADROOM="1.2"
FORMAT="table"
RATE_GP3_GB="0.115"
RATE_GP3_IOPS="0.02"
RATE_GP3_TP="0.08"
RATE_PIOPS_GB="0.125"
RATE_PIOPS="0.10"

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME --db-instance <id> [options]

Required:
  --db-instance <id>     RDS DB instance identifier

Optional:
  --days <n>             CloudWatch lookback days (default: 14)
  --region <region>      AWS region (default: \$AWS_DEFAULT_REGION or us-east-1)
  --profile <name>       AWS CLI profile
  --headroom <factor>     Headroom multiplier for sizing (default: 1.2)
  --rate-gp3-gb <n>      gp3 storage \$/GB-mo (default: 0.115)
  --rate-gp3-iops <n>    gp3 IOPS \$ above baseline (default: 0.02)
  --rate-gp3-tp <n>      gp3 throughput \$/MiB/s above baseline (default: 0.08)
  --rate-piops-gb <n>    io1/io2 storage \$/GB-mo (default: 0.125)
  --rate-piops <n>       io1/io2 provisioned IOPS \$ (default: 0.10)
  --format <fmt>         table | json | markdown (default: table)
  -h, --help             Show this help

Exit codes: 0 ok | 1 usage | 2 AWS error | 3 unsupported storage type
EOF
}

die_usage() {
  echo "Error: $*" >&2
  usage >&2
  exit 1
}

die_aws() {
  echo "Error: $*" >&2
  exit 2
}

die_unsupported() {
  echo "Error: $*" >&2
  exit 3
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die_aws "Missing required dependency: $1"
  fi
}

# Portable percentile: percentile_of_sorted <pct> <sorted_space_separated_numbers>
# Uses nearest-rank on a pre-sorted list (ascending).
percentile_of_sorted() {
  local pct="$1"
  shift
  # shellcheck disable=SC2206
  local -a vals=("$@")
  local n=${#vals[@]}
  if [[ "$n" -eq 0 ]]; then
    echo "null"
    return
  fi
  # index = ceil(pct/100 * n) - 1, clamped
  local idx
  idx="$(awk -v pct="$pct" -v n="$n" 'BEGIN {
    r = int((pct / 100.0) * n + 0.999999999)
    if (r < 1) r = 1
    if (r > n) r = n
    print r - 1
  }')"
  echo "${vals[$idx]}"
}

stats_from_values() {
  # stdin: one number per line; stdout: avg p95 p99 max (or nulls)
  local -a nums=()
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == "null" ]] && continue
    nums+=("$line")
  done

  local n=${#nums[@]}
  if [[ "$n" -eq 0 ]]; then
    echo "null null null null"
    return
  fi

  # Sort numerically
  local sorted
  sorted="$(printf '%s\n' "${nums[@]}" | LC_ALL=C sort -n)"
  local -a sarr=()
  while IFS= read -r line; do
    sarr+=("$line")
  done <<<"$sorted"

  local avg sum="0"
  local v
  for v in "${sarr[@]}"; do
    sum="$(awk -v a="$sum" -v b="$v" 'BEGIN { printf "%.10f", a + b }')"
  done
  avg="$(awk -v s="$sum" -v n="$n" 'BEGIN { printf "%.6f", s / n }')"

  local p95 p99 maxv
  p95="$(percentile_of_sorted 95 "${sarr[@]}")"
  p99="$(percentile_of_sorted 99 "${sarr[@]}")"
  maxv="${sarr[$((n - 1))]}"

  echo "$avg $p95 $p99 $maxv"
}

is_sqlserver() {
  [[ "$1" == sqlserver-* ]]
}

is_oracle() {
  [[ "$1" == "oracle-ee" || "$1" == "oracle-se2" || "$1" == "oracle-ee-cdb" || "$1" == "oracle-se2-cdb" ]]
}

clamp() {
  # clamp value lo hi
  awk -v v="$1" -v lo="$2" -v hi="$3" 'BEGIN {
    if (v < lo) v = lo
    if (v > hi) v = hi
    print v
  }'
}

ceil_int() {
  awk -v v="$1" 'BEGIN {
    if (v == int(v)) print int(v)
    else print int(v) + 1
  }'
}

round_iops() {
  # Round up to nearest 100 for cleaner Terraform values
  awk -v v="$1" 'BEGIN {
    if (v <= 0) { print 0; exit }
    r = int((v + 99) / 100) * 100
    print r
  }'
}

format_money() {
  awk -v v="$1" 'BEGIN { printf "%.2f", v }'
}

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-instance)
      [[ $# -ge 2 ]] || die_usage "--db-instance requires a value"
      DB_INSTANCE="$2"
      shift 2
      ;;
    --days)
      [[ $# -ge 2 ]] || die_usage "--days requires a value"
      DAYS="$2"
      shift 2
      ;;
    --region)
      [[ $# -ge 2 ]] || die_usage "--region requires a value"
      REGION="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || die_usage "--profile requires a value"
      PROFILE="$2"
      shift 2
      ;;
    --headroom)
      [[ $# -ge 2 ]] || die_usage "--headroom requires a value"
      HEADROOM="$2"
      shift 2
      ;;
    --rate-gp3-gb)
      [[ $# -ge 2 ]] || die_usage "--rate-gp3-gb requires a value"
      RATE_GP3_GB="$2"
      shift 2
      ;;
    --rate-gp3-iops)
      [[ $# -ge 2 ]] || die_usage "--rate-gp3-iops requires a value"
      RATE_GP3_IOPS="$2"
      shift 2
      ;;
    --rate-gp3-tp)
      [[ $# -ge 2 ]] || die_usage "--rate-gp3-tp requires a value"
      RATE_GP3_TP="$2"
      shift 2
      ;;
    --rate-piops-gb)
      [[ $# -ge 2 ]] || die_usage "--rate-piops-gb requires a value"
      RATE_PIOPS_GB="$2"
      shift 2
      ;;
    --rate-piops)
      [[ $# -ge 2 ]] || die_usage "--rate-piops requires a value"
      RATE_PIOPS="$2"
      shift 2
      ;;
    --format)
      [[ $# -ge 2 ]] || die_usage "--format requires a value"
      FORMAT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die_usage "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$DB_INSTANCE" ]] || die_usage "--db-instance is required"
[[ "$FORMAT" == "table" || "$FORMAT" == "json" || "$FORMAT" == "markdown" ]] \
  || die_usage "--format must be table, json, or markdown"
if [[ ! "$DAYS" =~ ^[0-9]+$ ]] || [[ "$DAYS" -lt 1 ]]; then
  die_usage "--days must be a positive integer"
fi

require_cmd aws
require_cmd jq

AWS_ARGS=(--region "$REGION" --output json)
if [[ -n "$PROFILE" ]]; then
  AWS_ARGS+=(--profile "$PROFILE")
fi

# Period: 60s for ≤3 days, else 300s
PERIOD=300
if [[ "$DAYS" -le 3 ]]; then
  PERIOD=60
fi

# --- Step 1: describe instance ---
DESCRIBE_JSON=""
if ! DESCRIBE_JSON="$(aws rds describe-db-instances \
  "${AWS_ARGS[@]}" \
  --db-instance-identifier "$DB_INSTANCE" 2>&1)"; then
  die_aws "aws rds describe-db-instances failed: $DESCRIBE_JSON"
fi

INSTANCE_JSON="$(echo "$DESCRIBE_JSON" | jq -c '.DBInstances[0] // empty')"
[[ -n "$INSTANCE_JSON" ]] || die_aws "DB instance not found: $DB_INSTANCE"

ENGINE="$(echo "$INSTANCE_JSON" | jq -r '.Engine')"
STORAGE_TYPE="$(echo "$INSTANCE_JSON" | jq -r '.StorageType')"
ALLOCATED="$(echo "$INSTANCE_JSON" | jq -r '.AllocatedStorage')"
PROV_IOPS="$(echo "$INSTANCE_JSON" | jq -r '.Iops // 0')"
MULTI_AZ="$(echo "$INSTANCE_JSON" | jq -r '.MultiAZ')"
INSTANCE_CLASS="$(echo "$INSTANCE_JSON" | jq -r '.DBInstanceClass')"
STATUS="$(echo "$INSTANCE_JSON" | jq -r '.DBInstanceStatus')"
DLV="$(echo "$INSTANCE_JSON" | jq -r '.DedicatedLogVolume // false')"

case "$STORAGE_TYPE" in
  io1|io2) ;;
  *)
    die_unsupported "Storage type '$STORAGE_TYPE' is not io1/io2; this assessment only covers PIOPS → gp3"
    ;;
esac

if [[ "$STATUS" == "stopped" ]]; then
  echo "Warning: instance status is 'stopped' — treat as a decommission candidate; metrics may be empty." >&2
fi

# --- Step 2: CloudWatch metrics ---
# Portable start time (GNU date or BSD date)
START=""
END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if START="$(date -u -d "${DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"; then
  :
elif START="$(date -u -v-"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"; then
  :
else
  # Fallback: epoch math
  NOW_EPOCH="$(date -u +%s)"
  START_EPOCH=$((NOW_EPOCH - DAYS * 86400))
  START="$(date -u -d "@${START_EPOCH}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$START_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"
fi

METRIC_NAMES=(
  ReadIOPS WriteIOPS
  ReadLatency WriteLatency
  ReadThroughput WriteThroughput
  DiskQueueDepth
  CPUUtilization FreeableMemory CPUCreditBalance
)

build_metric_queries() {
  local name id
  local parts=()
  for name in "${METRIC_NAMES[@]}"; do
    id="$(echo "$name" | tr '[:upper:]' '[:lower:]')"
    parts+=("$(jq -nc \
      --arg id "$id" \
      --arg name "$name" \
      --arg db "$DB_INSTANCE" \
      --argjson period "$PERIOD" \
      '{
        Id: $id,
        MetricStat: {
          Metric: {
            Namespace: "AWS/RDS",
            MetricName: $name,
            Dimensions: [{Name: "DBInstanceIdentifier", Value: $db}]
          },
          Period: $period,
          Stat: "Average"
        },
        ReturnData: true
      }')")
  done
  # Math expressions for totals (IOPS and throughput bytes/s)
  parts+=("$(jq -nc '{
    Id: "total_iops",
    Expression: "readiops + writeiops",
    Label: "TotalIOPS",
    ReturnData: true
  }')")
  parts+=("$(jq -nc '{
    Id: "total_tp",
    Expression: "readthroughput + writethroughput",
    Label: "TotalThroughput",
    ReturnData: true
  }')")

  printf '%s\n' "${parts[@]}" | jq -s '.'
}

QUERIES="$(build_metric_queries)"

METRIC_JSON=""
if ! METRIC_JSON="$(aws cloudwatch get-metric-data \
  "${AWS_ARGS[@]}" \
  --start-time "$START" \
  --end-time "$END" \
  --metric-data-queries "$QUERIES" 2>&1)"; then
  die_aws "aws cloudwatch get-metric-data failed: $METRIC_JSON"
fi

# Extract Values[] for a metric Id into newline-separated numbers
values_for_id() {
  local id="$1"
  echo "$METRIC_JSON" | jq -r --arg id "$id" '
    (.MetricDataResults // [])
    | map(select(.Id == $id))
    | .[0].Values // []
    | .[]
  '
}

# Compute stats: returns "avg p95 p99 max"
compute_stats() {
  local id="$1"
  values_for_id "$id" | stats_from_values
}

# Pick fields used for sizing / display (all 12 metrics queried; stats for key series)
read -r _ _ RIOPS_P99 _ <<<"$(compute_stats readiops)"
read -r _ _ WIOPS_P99 _ <<<"$(compute_stats writeiops)"
read -r _ _ TIOPS_P99 _ <<<"$(compute_stats total_iops)"
read -r _ _ RLAT_P99 _ <<<"$(compute_stats readlatency)"
read -r _ _ WLAT_P99 _ <<<"$(compute_stats writelatency)"
read -r _ _ TTP_P99 TTP_MAX <<<"$(compute_stats total_tp)"
read -r DQ_AVG _ _ _ <<<"$(compute_stats diskqueuedepth)"
read -r CPU_AVG _ _ CPU_MAX <<<"$(compute_stats cpuutilization)"
read -r MEM_AVG _ _ _ <<<"$(compute_stats freeablememory)"
read -r CRED_AVG _ _ _ <<<"$(compute_stats cpucreditbalance)"
# Individual read/write throughput series remain available via MetricDataResults if needed

EMPTY_METRICS=0
if [[ "$TIOPS_P99" == "null" ]]; then
  EMPTY_METRICS=1
  echo "Warning: no CloudWatch IOPS datapoints in the lookback window (stopped or near-idle instance)." >&2
fi

# Convert latency seconds → ms; throughput bytes/s → MiB/s
to_ms() {
  local v="$1"
  [[ "$v" == "null" ]] && { echo "null"; return; }
  awk -v v="$v" 'BEGIN { printf "%.4f", v * 1000 }'
}

to_mib() {
  local v="$1"
  [[ "$v" == "null" ]] && { echo "null"; return; }
  awk -v v="$v" 'BEGIN { printf "%.4f", v / 1048576 }'
}

RLAT_P99_MS="$(to_ms "$RLAT_P99")"
WLAT_P99_MS="$(to_ms "$WLAT_P99")"
TTP_P99_MIB="$(to_mib "$TTP_P99")"
TTP_MAX_MIB="$(to_mib "$TTP_MAX")"

# Peak throughput for display (prefer max, fall back to p99)
PEAK_TP_MIB="$TTP_MAX_MIB"
if [[ "$PEAK_TP_MIB" == "null" ]]; then
  PEAK_TP_MIB="$TTP_P99_MIB"
fi

# --- Step 4: gp3 sizing ---
# AWS gp3 baselines/limits (CHAP_Storage):
#   SQL Server: baseline 3K/125, max 80K/2K, no stripe threshold
#   Oracle: stripe at 200 GiB; below = 3K/125 only; above = baseline 12K/500, max 64K/4K
#   MySQL/MariaDB/PostgreSQL/Db2: stripe at 400 GiB; same pattern as Oracle above stripe
STRIPE_THRESHOLD=400
if is_oracle "$ENGINE"; then
  STRIPE_THRESHOLD=200
fi

GP3_BASE_IOPS=3000
GP3_BASE_TP=125
GP3_MAX_IOPS=64000
GP3_MAX_TP=4000
if is_sqlserver "$ENGINE"; then
  GP3_MAX_IOPS=80000
  GP3_MAX_TP=2000
fi

# Treat null metrics as 0 for sizing (with empty-metrics warning already emitted)
num_or_zero() {
  local v="$1"
  if [[ -z "$v" || "$v" == "null" ]]; then
    echo "0"
  else
    echo "$v"
  fi
}

P99_IOPS="$(num_or_zero "$TIOPS_P99")"
P99_TP_MIB="$(num_or_zero "$TTP_P99_MIB")"
NEED_IOPS="$(awk -v p="$P99_IOPS" -v h="$HEADROOM" 'BEGIN { printf "%.6f", p * h }')"
NEED_TP="$(awk -v p="$P99_TP_MIB" -v h="$HEADROOM" 'BEGIN { printf "%.6f", p * h }')"

GP3_IOPS=""
GP3_TP=""
GP3_IOPS_TF="null"
GP3_TP_TF="null"
FLAG_NEEDS_GROWTH=0
FLAG_OVER_MAX=0
# Billing baseline for extras (overridden for striped volumes)
BILL_BASE_IOPS=3000
BILL_BASE_TP=125

apply_tuned_gp3() {
  # Uses NEED_*, GP3_BASE_*, GP3_MAX_*; sets GP3_IOPS/TP/TF and FLAG_OVER_MAX
  if awk -v i="$NEED_IOPS" -v tp="$NEED_TP" -v bi="$GP3_BASE_IOPS" -v bt="$GP3_BASE_TP" \
    'BEGIN { exit !((i <= bi) && (tp <= bt)) }'; then
    GP3_IOPS=""
    GP3_TP=""
    GP3_IOPS_TF="null"
    GP3_TP_TF="null"
    return
  fi
  GP3_IOPS="$(clamp "$NEED_IOPS" "$GP3_BASE_IOPS" "$GP3_MAX_IOPS")"
  GP3_TP="$(clamp "$NEED_TP" "$GP3_BASE_TP" "$GP3_MAX_TP")"
  MIN_IOPS_FOR_TP="$(awk -v tp="$GP3_TP" 'BEGIN { printf "%.6f", tp * 4 }')"
  GP3_IOPS="$(awk -v a="$GP3_IOPS" -v b="$MIN_IOPS_FOR_TP" 'BEGIN { print (a > b ? a : b) }')"
  GP3_IOPS="$(clamp "$GP3_IOPS" "$GP3_BASE_IOPS" "$GP3_MAX_IOPS")"
  GP3_IOPS="$(round_iops "$GP3_IOPS")"
  # After rounding, keep within max and re-clamp TP relationship floor
  if awk -v i="$GP3_IOPS" -v m="$GP3_MAX_IOPS" 'BEGIN { exit !(i > m) }'; then
    GP3_IOPS="$GP3_MAX_IOPS"
  fi
  GP3_TP="$(ceil_int "$GP3_TP")"
  if awk -v n="$NEED_IOPS" -v m="$GP3_MAX_IOPS" 'BEGIN { exit !(n > m) }'; then
    FLAG_OVER_MAX=1
  fi
  GP3_IOPS_TF="$GP3_IOPS"
  GP3_TP_TF="$GP3_TP"
}

if is_sqlserver "$ENGINE"; then
  BILL_BASE_IOPS=3000
  BILL_BASE_TP=125
  apply_tuned_gp3
elif awk -v s="$ALLOCATED" -v t="$STRIPE_THRESHOLD" 'BEGIN { exit !(s < t) }'; then
  # Below stripe threshold: baseline only (3K / 125)
  BILL_BASE_IOPS=3000
  BILL_BASE_TP=125
  GP3_BASE_IOPS=3000
  GP3_BASE_TP=125
  if awk -v i="$NEED_IOPS" -v tp="$NEED_TP" 'BEGIN { exit !((i <= 3000) && (tp <= 125)) }'; then
    GP3_IOPS=""
    GP3_TP=""
    GP3_IOPS_TF="null"
    GP3_TP_TF="null"
  else
    FLAG_NEEDS_GROWTH=1
    GP3_IOPS=""
    GP3_TP=""
    GP3_IOPS_TF="null"
    GP3_TP_TF="null"
  fi
else
  # Striped: included baseline 12K / 500; provisionable 12K–64K / 500–4K
  BILL_BASE_IOPS=12000
  BILL_BASE_TP=500
  GP3_BASE_IOPS=12000
  GP3_BASE_TP=500
  GP3_MAX_IOPS=64000
  GP3_MAX_TP=4000
  apply_tuned_gp3
  # iops ≤ 500 × storage_gb
  if [[ -n "$GP3_IOPS" ]]; then
    MAX_BY_SIZE="$(awk -v s="$ALLOCATED" 'BEGIN { print 500 * s }')"
    if awk -v i="$GP3_IOPS" -v m="$MAX_BY_SIZE" 'BEGIN { exit !(i > m) }'; then
      FLAG_NEEDS_GROWTH=1
    fi
  fi
fi

# Cost uses billed IOPS/TP (baseline counts even when TF null)
BILL_IOPS="${GP3_IOPS:-$BILL_BASE_IOPS}"
BILL_TP="${GP3_TP:-$BILL_BASE_TP}"
if [[ "$FLAG_NEEDS_GROWTH" -eq 1 && -z "$GP3_IOPS" ]]; then
  # No valid gp3 config — cost compare against applicable baseline for informational only
  BILL_IOPS="$BILL_BASE_IOPS"
  BILL_TP="$BILL_BASE_TP"
fi

MULTI_FACTOR=1
if [[ "$MULTI_AZ" == "true" ]]; then
  MULTI_FACTOR=2
fi

CURRENT_COST="$(awk -v gb="$ALLOCATED" -v rgb="$RATE_PIOPS_GB" -v iops="$PROV_IOPS" -v riops="$RATE_PIOPS" -v m="$MULTI_FACTOR" \
  'BEGIN { printf "%.6f", (gb * rgb + iops * riops) * m }')"

GP3_COST="$(awk -v gb="$ALLOCATED" -v rgb="$RATE_GP3_GB" \
  -v iops="$BILL_IOPS" -v riops="$RATE_GP3_IOPS" \
  -v tp="$BILL_TP" -v rtp="$RATE_GP3_TP" \
  -v bi="$BILL_BASE_IOPS" -v bt="$BILL_BASE_TP" \
  -v m="$MULTI_FACTOR" \
  'BEGIN {
    iops_extra = (iops > bi) ? (iops - bi) : 0
    tp_extra = (tp > bt) ? (tp - bt) : 0
    printf "%.6f", (gb * rgb + iops_extra * riops + tp_extra * rtp) * m
  }')"

SAVINGS_ABS="$(awk -v c="$CURRENT_COST" -v g="$GP3_COST" 'BEGIN { printf "%.6f", c - g }')"
SAVINGS_PCT="$(awk -v c="$CURRENT_COST" -v g="$GP3_COST" 'BEGIN {
  if (c <= 0) { print "0"; exit }
  printf "%.2f", (c - g) / c * 100
}')"

# Latency signal (warning only — does not auto-STAY; confirm hard SLA with app owner)
TIGHT_LATENCY=0
if [[ "$RLAT_P99_MS" != "null" && "$WLAT_P99_MS" != "null" ]]; then
  if awk -v r="$RLAT_P99_MS" -v w="$WLAT_P99_MS" 'BEGIN { exit !((r < 1.0) && (w < 1.0)) }'; then
    TIGHT_LATENCY=1
  fi
fi

# Queue pressure
QUEUE_PRESSURE=0
if [[ "$DQ_AVG" != "null" && "$PROV_IOPS" -gt 0 ]]; then
  THRESH="$(awk -v p="$PROV_IOPS" 'BEGIN { printf "%.6f", 10 * (p / 10000) }')"
  if awk -v d="$DQ_AVG" -v t="$THRESH" 'BEGIN { exit !(d > t) }'; then
    QUEUE_PRESSURE=1
  fi
fi

# --- Decision ---
DECISION=""
DECISION_REASON=""

if [[ "$DLV" == "true" ]]; then
  DECISION="BLOCKER"
  DECISION_REASON="Dedicated Log Volume is enabled (io1/io2 only)"
elif [[ "$STATUS" == "stopped" || "$EMPTY_METRICS" -eq 1 ]]; then
  DECISION="OPTIONAL"
  DECISION_REASON="stopped or empty metrics — decommission candidate or verify traffic before migrating"
elif [[ "$FLAG_OVER_MAX" -eq 1 ]]; then
  DECISION="STAY"
  DECISION_REASON="need_iops (${NEED_IOPS}) exceeds gp3 max (${GP3_MAX_IOPS})"
elif [[ "$FLAG_NEEDS_GROWTH" -eq 1 ]]; then
  DECISION="CONDITIONAL"
  DECISION_REASON="storage below stripe threshold or IOPS>size ratio; grow storage to ≥${STRIPE_THRESHOLD} GiB or stay on PIOPS"
elif awk -v s="$SAVINGS_PCT" 'BEGIN { exit !(s >= 10) }'; then
  DECISION="MIGRATE"
  DECISION_REASON="estimated savings ${SAVINGS_PCT}% ≥ 10%"
else
  DECISION="OPTIONAL"
  DECISION_REASON="estimated savings ${SAVINGS_PCT}% < 10% (fleet standardization only)"
fi

DECISION_ICON=""
case "$DECISION" in
  MIGRATE) DECISION_ICON="✅ MIGRATE" ;;
  OPTIONAL) DECISION_ICON="⚪ OPTIONAL" ;;
  CONDITIONAL) DECISION_ICON="⚠️ CONDITIONAL" ;;
  STAY) DECISION_ICON="🛑 STAY" ;;
  BLOCKER) DECISION_ICON="🚫 BLOCKER" ;;
esac

MULTI_AZ_LABEL="No"
[[ "$MULTI_AZ" == "true" ]] && MULTI_AZ_LABEL="Yes"

CURRENT_COST_F="$(format_money "$CURRENT_COST")"
GP3_COST_F="$(format_money "$GP3_COST")"
SAVINGS_ABS_F="$(format_money "$SAVINGS_ABS")"

# Display helpers for nullable metrics
disp_int() {
  local v="$1"
  [[ "$v" == "null" || -z "$v" ]] && { echo "n/a"; return; }
  awk -v v="$v" 'BEGIN { printf "%d", int(v + 0.5) }'
}

disp_float() {
  local v="$1" places="${2:-1}"
  [[ "$v" == "null" || -z "$v" ]] && { echo "n/a"; return; }
  awk -v v="$v" -v p="$places" 'BEGIN { printf "%.*f", p, v }'
}

TF_IOPS_LINE="db_instance_iops               = ${GP3_IOPS_TF}"
TF_TP_LINE="db_instance_storage_throughput = ${GP3_TP_TF}"

emit_table() {
  cat <<EOF
=== RDS Storage Migration Assessment ===
Instance: ${DB_INSTANCE} | Engine: ${ENGINE} | Region: ${REGION}

Current (${STORAGE_TYPE}):
  Storage: ${ALLOCATED} GiB | IOPS: ${PROV_IOPS} | Multi-AZ: ${MULTI_AZ_LABEL}
  Instance class: ${INSTANCE_CLASS} | Status: ${STATUS}
  Monthly Cost: \$${CURRENT_COST_F}

Observed Metrics (${DAYS}-day lookback, period ${PERIOD}s):
  p99 ReadIOPS:     $(disp_int "$RIOPS_P99")
  p99 WriteIOPS:    $(disp_int "$WIOPS_P99")
  p99 TotalIOPS:    $(disp_int "$TIOPS_P99")
  p99 ReadLatency:  $(disp_float "$RLAT_P99_MS" 2) ms
  p99 WriteLatency: $(disp_float "$WLAT_P99_MS" 2) ms
  Avg DiskQueueDepth: $(disp_float "$DQ_AVG" 2)
  Peak Throughput:    $(disp_float "$PEAK_TP_MIB" 1) MiB/s
  Avg CPUUtilization: $(disp_float "$CPU_AVG" 1)% (max $(disp_float "$CPU_MAX" 1)%)
  Avg FreeableMemory: $(disp_int "$MEM_AVG") bytes
  Avg CPUCreditBalance: $(disp_float "$CRED_AVG" 1)
EOF

  if [[ "$EMPTY_METRICS" -eq 1 ]]; then
    echo "  Note: metrics empty/near-zero — verify instance is running and has traffic."
  fi
  if [[ "$QUEUE_PRESSURE" -eq 1 ]]; then
    echo "  Note: DiskQueueDepth suggests I/O pressure relative to provisioned IOPS."
  fi
  if [[ "$TIGHT_LATENCY" -eq 1 ]]; then
    echo "  Note: p99 latency < 1 ms — confirm with the app owner whether a hard sub-ms SLA requires staying on io2."
  fi

  echo
  echo "Recommended gp3 Config:"
  if [[ "$FLAG_NEEDS_GROWTH" -eq 1 && "$DECISION" == "CONDITIONAL" ]]; then
    cat <<EOF
  # CONDITIONAL: grow allocated storage to ≥ ${STRIPE_THRESHOLD} GiB before tuning, or stay on ${STORAGE_TYPE}
  db_instance_storage_type       = "gp3"
  ${TF_IOPS_LINE}
  ${TF_TP_LINE}
EOF
  else
    cat <<EOF
  db_instance_storage_type       = "gp3"
  ${TF_IOPS_LINE}
  ${TF_TP_LINE}
EOF
  fi

  cat <<EOF

Estimated gp3 Monthly Cost: \$${GP3_COST_F}
Estimated Savings: ${SAVINGS_PCT}% (\$${SAVINGS_ABS_F}/mo)

Decision: ${DECISION_ICON}
Reason: ${DECISION_REASON}
EOF
}

emit_markdown() {
  cat <<EOF
# RDS Storage Migration Assessment

| Field | Value |
|-------|-------|
| Instance | \`${DB_INSTANCE}\` |
| Engine | \`${ENGINE}\` |
| Region | \`${REGION}\` |
| Current storage | \`${STORAGE_TYPE}\`, ${ALLOCATED} GiB, ${PROV_IOPS} IOPS |
| Multi-AZ | ${MULTI_AZ_LABEL} |
| Current cost | \$${CURRENT_COST_F}/mo |
| p99 TotalIOPS | $(disp_int "$TIOPS_P99") |
| p99 ReadLatency | $(disp_float "$RLAT_P99_MS" 2) ms |
| p99 WriteLatency | $(disp_float "$WLAT_P99_MS" 2) ms |
| Peak throughput | $(disp_float "$PEAK_TP_MIB" 1) MiB/s |
| gp3 IOPS | ${GP3_IOPS_TF} |
| gp3 throughput | ${GP3_TP_TF} |
| gp3 cost | \$${GP3_COST_F}/mo |
| Savings | ${SAVINGS_PCT}% (\$${SAVINGS_ABS_F}/mo) |
| **Decision** | **${DECISION}** |

\`\`\`hcl
db_instance_storage_type       = "gp3"
${TF_IOPS_LINE}
${TF_TP_LINE}
\`\`\`

Reason: ${DECISION_REASON}
EOF
}

emit_json() {
  jq -nc \
    --arg instance "$DB_INSTANCE" \
    --arg engine "$ENGINE" \
    --arg region "$REGION" \
    --arg storage_type "$STORAGE_TYPE" \
    --argjson allocated "$ALLOCATED" \
    --argjson prov_iops "$PROV_IOPS" \
    --arg multi_az "$MULTI_AZ" \
    --arg instance_class "$INSTANCE_CLASS" \
    --arg status "$STATUS" \
    --argjson dlv "$DLV" \
    --argjson days "$DAYS" \
    --argjson period "$PERIOD" \
    --argjson current_cost "$CURRENT_COST" \
    --argjson gp3_cost "$GP3_COST" \
    --argjson savings_abs "$SAVINGS_ABS" \
    --argjson savings_pct "$SAVINGS_PCT" \
    --arg decision "$DECISION" \
    --arg reason "$DECISION_REASON" \
    --arg gp3_iops_tf "$GP3_IOPS_TF" \
    --arg gp3_tp_tf "$GP3_TP_TF" \
    --arg riops_p99 "$RIOPS_P99" \
    --arg wiops_p99 "$WIOPS_P99" \
    --arg tiops_p99 "$TIOPS_P99" \
    --arg rlat_p99_ms "$RLAT_P99_MS" \
    --arg wlat_p99_ms "$WLAT_P99_MS" \
    --arg dq_avg "$DQ_AVG" \
    --arg peak_tp_mib "$PEAK_TP_MIB" \
    --arg need_iops "$NEED_IOPS" \
    --arg need_tp "$NEED_TP" \
    --arg cpu_avg "$CPU_AVG" \
    --arg cpu_max "$CPU_MAX" \
    --arg mem_avg "$MEM_AVG" \
    --arg cred_avg "$CRED_AVG" \
    --argjson empty_metrics "$EMPTY_METRICS" \
    '{
      instance: $instance,
      engine: $engine,
      region: $region,
      current: {
        storage_type: $storage_type,
        allocated_storage: $allocated,
        iops: $prov_iops,
        multi_az: ($multi_az == "true"),
        instance_class: $instance_class,
        status: $status,
        dedicated_log_volume: $dlv,
        monthly_cost: $current_cost
      },
      metrics: {
        lookback_days: $days,
        period_seconds: $period,
        p99_read_iops: (if $riops_p99 == "null" then null else ($riops_p99|tonumber) end),
        p99_write_iops: (if $wiops_p99 == "null" then null else ($wiops_p99|tonumber) end),
        p99_total_iops: (if $tiops_p99 == "null" then null else ($tiops_p99|tonumber) end),
        p99_read_latency_ms: (if $rlat_p99_ms == "null" then null else ($rlat_p99_ms|tonumber) end),
        p99_write_latency_ms: (if $wlat_p99_ms == "null" then null else ($wlat_p99_ms|tonumber) end),
        avg_disk_queue_depth: (if $dq_avg == "null" then null else ($dq_avg|tonumber) end),
        peak_throughput_mib_s: (if $peak_tp_mib == "null" then null else ($peak_tp_mib|tonumber) end),
        avg_cpu_utilization: (if $cpu_avg == "null" then null else ($cpu_avg|tonumber) end),
        max_cpu_utilization: (if $cpu_max == "null" then null else ($cpu_max|tonumber) end),
        avg_freeable_memory: (if $mem_avg == "null" then null else ($mem_avg|tonumber) end),
        avg_cpu_credit_balance: (if $cred_avg == "null" then null else ($cred_avg|tonumber) end),
        empty_metrics: ($empty_metrics == 1)
      },
      sizing: {
        need_iops: ($need_iops|tonumber),
        need_throughput_mib_s: ($need_tp|tonumber),
        db_instance_storage_type: "gp3",
        db_instance_iops: (if $gp3_iops_tf == "null" then null else ($gp3_iops_tf|tonumber) end),
        db_instance_storage_throughput: (if $gp3_tp_tf == "null" then null else ($gp3_tp_tf|tonumber) end)
      },
      cost: {
        gp3_monthly: $gp3_cost,
        savings_monthly: $savings_abs,
        savings_pct: $savings_pct
      },
      decision: $decision,
      reason: $reason
    }'
}

case "$FORMAT" in
  table) emit_table ;;
  markdown) emit_markdown ;;
  json) emit_json ;;
esac

exit 0
