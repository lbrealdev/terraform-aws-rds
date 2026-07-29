#!/usr/bin/env bash
# measure-rds-storage.sh — Size equivalent RDS storage settings from CloudWatch demand.
#
# Given an instance on io1/io2 or gp3, recommend Terraform knobs for the other
# family (gp3 or io2) so performance holds; report cost impact as a side effect.
#
# Usage:
#   ./scripts/measure-rds-storage.sh --db-instance <id> [options]
#
# Exit codes:
#   0  ok
#   1  usage / argument error
#   2  AWS / dependency error
#   3  unsupported storage type or invalid direction
#
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

# Defaults
DB_INSTANCE=""
DAYS=14
# Prefer AWS_REGION, then AWS_DEFAULT_REGION, then us-east-1
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PROFILE=""
HEADROOM="1.2"
FORMAT="table"
TARGET="" # auto: io1/io2→gp3, gp3→io2
RATE_GP3_GB="0.115"
RATE_GP3_IOPS="0.02"
RATE_GP3_TP="0.08"
RATE_PIOPS_GB="0.125"
RATE_PIOPS="0.10"

log() {
  echo "[$SCRIPT_NAME] $*" >&2
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME --db-instance <id> [options]

Size equivalent RDS storage Terraform settings from CloudWatch demand
(io1/io2 → gp3, or gp3 → io2) so a storage-type change does not undersize
performance. Cost delta is informational.

Required:
  --db-instance <id>     RDS DB instance identifier

Optional:
  --target <type>        Destination storage: gp3 | io2
                         (default: auto from current type)
  --days <n>             CloudWatch lookback days (default: 14; use 1 or 3 for smoke tests)
  --region <region>      AWS region (default: \$AWS_REGION, \$AWS_DEFAULT_REGION, or us-east-1)
  --profile <name>       AWS CLI profile
  --headroom <factor>     Headroom multiplier for sizing (default: 1.2)
  --rate-gp3-gb <n>      gp3 storage \$/GB-mo (default: 0.115)
  --rate-gp3-iops <n>    gp3 IOPS \$ above baseline (default: 0.02)
  --rate-gp3-tp <n>      gp3 throughput \$/MiB/s above baseline (default: 0.08)
  --rate-piops-gb <n>    io1/io2 storage \$/GB-mo (default: 0.125)
  --rate-piops <n>       io1/io2 provisioned IOPS \$ (default: 0.10)
  --format <fmt>         table | json | markdown (default: table)
  -h, --help             Show this help

Exit codes: 0 ok | 1 usage | 2 AWS error | 3 unsupported storage / invalid direction
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
    --target)
      [[ $# -ge 2 ]] || die_usage "--target requires a value"
      TARGET="$2"
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
if [[ -n "$TARGET" && "$TARGET" != "gp3" && "$TARGET" != "io2" ]]; then
  die_usage "--target must be gp3 or io2"
fi
if [[ ! "$DAYS" =~ ^[0-9]+$ ]] || [[ "$DAYS" -lt 1 ]]; then
  die_usage "--days must be a positive integer"
fi

require_cmd aws
require_cmd jq

AWS_ARGS=(--region "$REGION" --output json)
if [[ -n "$PROFILE" ]]; then
  AWS_ARGS+=(--profile "$PROFILE")
fi

PERIOD=300
if [[ "$DAYS" -le 3 ]]; then
  PERIOD=60
fi

log "Region: ${REGION}${PROFILE:+ (profile $PROFILE)}"
log "Describing DB instance: ${DB_INSTANCE}"

DESCRIBE_JSON=""
if ! DESCRIBE_JSON="$(aws rds describe-db-instances \
  "${AWS_ARGS[@]}" \
  --db-instance-identifier "$DB_INSTANCE" 2>&1)"; then
  die_aws "aws rds describe-db-instances failed: $DESCRIBE_JSON"
fi

INSTANCE_JSON="$(echo "$DESCRIBE_JSON" | jq -c '.DBInstances[0] // empty')"
[[ -n "$INSTANCE_JSON" ]] || die_aws "DB instance not found: $DB_INSTANCE (check --region)"

ENGINE="$(echo "$INSTANCE_JSON" | jq -r '.Engine')"
STORAGE_TYPE="$(echo "$INSTANCE_JSON" | jq -r '.StorageType')"
ALLOCATED="$(echo "$INSTANCE_JSON" | jq -r '.AllocatedStorage')"
PROV_IOPS="$(echo "$INSTANCE_JSON" | jq -r '.Iops // 0')"
STORAGE_TP="$(echo "$INSTANCE_JSON" | jq -r '.StorageThroughput // 0')"
MULTI_AZ="$(echo "$INSTANCE_JSON" | jq -r '.MultiAZ')"
INSTANCE_CLASS="$(echo "$INSTANCE_JSON" | jq -r '.DBInstanceClass')"
STATUS="$(echo "$INSTANCE_JSON" | jq -r '.DBInstanceStatus')"
DLV="$(echo "$INSTANCE_JSON" | jq -r '.DedicatedLogVolume // false')"

# Resolve target direction
case "$STORAGE_TYPE" in
  io1|io2)
    DEFAULT_TARGET="gp3"
    ;;
  gp3)
    DEFAULT_TARGET="io2"
    ;;
  *)
    die_unsupported "Storage type '$STORAGE_TYPE' is unsupported; only io1, io2, or gp3"
    ;;
esac

if [[ -z "$TARGET" ]]; then
  TARGET="$DEFAULT_TARGET"
fi

if [[ "$TARGET" == "$STORAGE_TYPE" ]]; then
  die_unsupported "Target '$TARGET' matches current storage type; nothing to size"
fi
if [[ "$STORAGE_TYPE" == "gp3" && "$TARGET" != "io2" ]]; then
  die_unsupported "From gp3, only --target io2 is supported"
fi
if [[ "$STORAGE_TYPE" == "io1" || "$STORAGE_TYPE" == "io2" ]]; then
  if [[ "$TARGET" != "gp3" ]]; then
    die_unsupported "From io1/io2, only --target gp3 is supported"
  fi
fi

log "Direction: ${STORAGE_TYPE} → ${TARGET}"

if [[ "$STATUS" == "stopped" ]]; then
  log "Warning: instance status is 'stopped' — metrics may be empty."
fi

# --- CloudWatch metrics ---
START=""
END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if START="$(date -u -d "${DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"; then
  :
elif START="$(date -u -v-"${DAYS}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"; then
  :
else
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

log "Fetching CloudWatch metrics (--days ${DAYS}, period ${PERIOD}s)…"

METRIC_JSON=""
if ! METRIC_JSON="$(aws cloudwatch get-metric-data \
  "${AWS_ARGS[@]}" \
  --start-time "$START" \
  --end-time "$END" \
  --metric-data-queries "$QUERIES" 2>&1)"; then
  die_aws "aws cloudwatch get-metric-data failed: $METRIC_JSON"
fi

log "Metrics received; computing stats…"

values_for_id() {
  local id="$1"
  echo "$METRIC_JSON" | jq -r --arg id "$id" '
    (.MetricDataResults // [])
    | map(select(.Id == $id))
    | .[0].Values // []
    | .[]
  '
}

compute_stats() {
  local id="$1"
  values_for_id "$id" | stats_from_values
}

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

EMPTY_METRICS=0
if [[ "$TIOPS_P99" == "null" ]]; then
  EMPTY_METRICS=1
  log "Warning: no CloudWatch IOPS datapoints in the lookback window."
fi

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

PEAK_TP_MIB="$TTP_MAX_MIB"
if [[ "$PEAK_TP_MIB" == "null" ]]; then
  PEAK_TP_MIB="$TTP_P99_MIB"
fi

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

log "Sizing ${TARGET} from demand (need_iops≈$(ceil_int "$NEED_IOPS"), need_tp≈$(awk -v v="$NEED_TP" 'BEGIN { printf "%.1f", v }') MiB/s)…"

# --- Sizing outputs ---
REC_STORAGE_TYPE="$TARGET"
REC_IOPS_TF="null"
REC_TP_TF="null"
FLAG_NEEDS_GROWTH=0
FLAG_OVER_MAX=0
FLAG_DLV_BLOCKER=0
RECOMMENDATION_OK=1

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
BILL_BASE_IOPS=3000
BILL_BASE_TP=125
GP3_IOPS=""
GP3_TP=""

# io2 provisioned IOPS range (practical Nitro-era ceiling used in this methodology)
IO2_MIN_IOPS=1000
IO2_MAX_IOPS=256000
IO2_IOPS=""

apply_tuned_gp3() {
  if awk -v i="$NEED_IOPS" -v tp="$NEED_TP" -v bi="$GP3_BASE_IOPS" -v bt="$GP3_BASE_TP" \
    'BEGIN { exit !((i <= bi) && (tp <= bt)) }'; then
    GP3_IOPS=""
    GP3_TP=""
    REC_IOPS_TF="null"
    REC_TP_TF="null"
    return
  fi
  GP3_IOPS="$(clamp "$NEED_IOPS" "$GP3_BASE_IOPS" "$GP3_MAX_IOPS")"
  GP3_TP="$(clamp "$NEED_TP" "$GP3_BASE_TP" "$GP3_MAX_TP")"
  MIN_IOPS_FOR_TP="$(awk -v tp="$GP3_TP" 'BEGIN { printf "%.6f", tp * 4 }')"
  GP3_IOPS="$(awk -v a="$GP3_IOPS" -v b="$MIN_IOPS_FOR_TP" 'BEGIN { print (a > b ? a : b) }')"
  GP3_IOPS="$(clamp "$GP3_IOPS" "$GP3_BASE_IOPS" "$GP3_MAX_IOPS")"
  GP3_IOPS="$(round_iops "$GP3_IOPS")"
  if awk -v i="$GP3_IOPS" -v m="$GP3_MAX_IOPS" 'BEGIN { exit !(i > m) }'; then
    GP3_IOPS="$GP3_MAX_IOPS"
  fi
  GP3_TP="$(ceil_int "$GP3_TP")"
  if awk -v n="$NEED_IOPS" -v m="$GP3_MAX_IOPS" 'BEGIN { exit !(n > m) }'; then
    FLAG_OVER_MAX=1
  fi
  REC_IOPS_TF="$GP3_IOPS"
  REC_TP_TF="$GP3_TP"
}

size_to_gp3() {
  if [[ "$DLV" == "true" ]]; then
    FLAG_DLV_BLOCKER=1
    RECOMMENDATION_OK=0
    REC_IOPS_TF="null"
    REC_TP_TF="null"
    return
  fi

  if is_sqlserver "$ENGINE"; then
    BILL_BASE_IOPS=3000
    BILL_BASE_TP=125
    apply_tuned_gp3
  elif awk -v s="$ALLOCATED" -v t="$STRIPE_THRESHOLD" 'BEGIN { exit !(s < t) }'; then
    BILL_BASE_IOPS=3000
    BILL_BASE_TP=125
    GP3_BASE_IOPS=3000
    GP3_BASE_TP=125
    if awk -v i="$NEED_IOPS" -v tp="$NEED_TP" 'BEGIN { exit !((i <= 3000) && (tp <= 125)) }'; then
      GP3_IOPS=""
      GP3_TP=""
      REC_IOPS_TF="null"
      REC_TP_TF="null"
    else
      FLAG_NEEDS_GROWTH=1
      RECOMMENDATION_OK=0
      GP3_IOPS=""
      GP3_TP=""
      REC_IOPS_TF="null"
      REC_TP_TF="null"
    fi
  else
    BILL_BASE_IOPS=12000
    BILL_BASE_TP=500
    GP3_BASE_IOPS=12000
    GP3_BASE_TP=500
    GP3_MAX_IOPS=64000
    GP3_MAX_TP=4000
    apply_tuned_gp3
    if [[ -n "$GP3_IOPS" ]]; then
      MAX_BY_SIZE="$(awk -v s="$ALLOCATED" 'BEGIN { print 500 * s }')"
      if awk -v i="$GP3_IOPS" -v m="$MAX_BY_SIZE" 'BEGIN { exit !(i > m) }'; then
        FLAG_NEEDS_GROWTH=1
      fi
    fi
  fi

  if [[ "$FLAG_OVER_MAX" -eq 1 ]]; then
    RECOMMENDATION_OK=0
  fi
}

size_to_io2() {
  # Determine gp3 billing baseline for *current* cost when source is gp3
  if is_sqlserver "$ENGINE"; then
    BILL_BASE_IOPS=3000
    BILL_BASE_TP=125
  elif awk -v s="$ALLOCATED" -v t="$STRIPE_THRESHOLD" 'BEGIN { exit !(s < t) }'; then
    BILL_BASE_IOPS=3000
    BILL_BASE_TP=125
  else
    BILL_BASE_IOPS=12000
    BILL_BASE_TP=500
  fi

  IO2_IOPS="$(ceil_int "$NEED_IOPS")"
  IO2_IOPS="$(round_iops "$IO2_IOPS")"
  if awk -v i="$IO2_IOPS" -v lo="$IO2_MIN_IOPS" 'BEGIN { exit !(i < lo) }'; then
    IO2_IOPS="$IO2_MIN_IOPS"
  fi
  if awk -v n="$NEED_IOPS" -v m="$IO2_MAX_IOPS" 'BEGIN { exit !(n > m) }'; then
    FLAG_OVER_MAX=1
    RECOMMENDATION_OK=0
    IO2_IOPS="$IO2_MAX_IOPS"
  fi
  if awk -v i="$IO2_IOPS" -v m="$IO2_MAX_IOPS" 'BEGIN { exit !(i > m) }'; then
    IO2_IOPS="$IO2_MAX_IOPS"
  fi
  REC_IOPS_TF="$IO2_IOPS"
  REC_TP_TF="null"
}

if [[ "$TARGET" == "gp3" ]]; then
  size_to_gp3
else
  size_to_io2
fi

MULTI_FACTOR=1
if [[ "$MULTI_AZ" == "true" ]]; then
  MULTI_FACTOR=2
fi

# Current monthly cost
if [[ "$STORAGE_TYPE" == "gp3" ]]; then
  CUR_IOPS="$(num_or_zero "$PROV_IOPS")"
  CUR_TP="$(num_or_zero "$STORAGE_TP")"
  # If IOPS/TP unset (0), bill at included baseline
  if awk -v i="$CUR_IOPS" 'BEGIN { exit !(i <= 0) }'; then CUR_IOPS="$BILL_BASE_IOPS"; fi
  if awk -v t="$CUR_TP" 'BEGIN { exit !(t <= 0) }'; then CUR_TP="$BILL_BASE_TP"; fi
  CURRENT_COST="$(awk -v gb="$ALLOCATED" -v rgb="$RATE_GP3_GB" \
    -v iops="$CUR_IOPS" -v riops="$RATE_GP3_IOPS" \
    -v tp="$CUR_TP" -v rtp="$RATE_GP3_TP" \
    -v bi="$BILL_BASE_IOPS" -v bt="$BILL_BASE_TP" \
    -v m="$MULTI_FACTOR" \
    'BEGIN {
      iops_extra = (iops > bi) ? (iops - bi) : 0
      tp_extra = (tp > bt) ? (tp - bt) : 0
      printf "%.6f", (gb * rgb + iops_extra * riops + tp_extra * rtp) * m
    }')"
else
  CURRENT_COST="$(awk -v gb="$ALLOCATED" -v rgb="$RATE_PIOPS_GB" -v iops="$PROV_IOPS" -v riops="$RATE_PIOPS" -v m="$MULTI_FACTOR" \
    'BEGIN { printf "%.6f", (gb * rgb + iops * riops) * m }')"
fi

# Recommended monthly cost
if [[ "$TARGET" == "gp3" ]]; then
  BILL_IOPS="${GP3_IOPS:-$BILL_BASE_IOPS}"
  BILL_TP="${GP3_TP:-$BILL_BASE_TP}"
  if [[ "$FLAG_NEEDS_GROWTH" -eq 1 && -z "$GP3_IOPS" ]]; then
    BILL_IOPS="$BILL_BASE_IOPS"
    BILL_TP="$BILL_BASE_TP"
  fi
  REC_COST="$(awk -v gb="$ALLOCATED" -v rgb="$RATE_GP3_GB" \
    -v iops="$BILL_IOPS" -v riops="$RATE_GP3_IOPS" \
    -v tp="$BILL_TP" -v rtp="$RATE_GP3_TP" \
    -v bi="$BILL_BASE_IOPS" -v bt="$BILL_BASE_TP" \
    -v m="$MULTI_FACTOR" \
    'BEGIN {
      iops_extra = (iops > bi) ? (iops - bi) : 0
      tp_extra = (tp > bt) ? (tp - bt) : 0
      printf "%.6f", (gb * rgb + iops_extra * riops + tp_extra * rtp) * m
    }')"
else
  BILL_IO2="${IO2_IOPS:-$IO2_MIN_IOPS}"
  REC_COST="$(awk -v gb="$ALLOCATED" -v rgb="$RATE_PIOPS_GB" -v iops="$BILL_IO2" -v riops="$RATE_PIOPS" -v m="$MULTI_FACTOR" \
    'BEGIN { printf "%.6f", (gb * rgb + iops * riops) * m }')"
fi

COST_DELTA="$(awk -v c="$CURRENT_COST" -v r="$REC_COST" 'BEGIN { printf "%.6f", c - r }')"
COST_DELTA_PCT="$(awk -v c="$CURRENT_COST" -v r="$REC_COST" 'BEGIN {
  if (c <= 0) { print "0"; exit }
  printf "%.2f", (c - r) / c * 100
}')"

TIGHT_LATENCY=0
if [[ "$RLAT_P99_MS" != "null" && "$WLAT_P99_MS" != "null" ]]; then
  if awk -v r="$RLAT_P99_MS" -v w="$WLAT_P99_MS" 'BEGIN { exit !((r < 1.0) && (w < 1.0)) }'; then
    TIGHT_LATENCY=1
  fi
fi

QUEUE_PRESSURE=0
if [[ "$DQ_AVG" != "null" ]]; then
  # Relative to provisioned IOPS when on PIOPS; otherwise use need_iops
  REF_IOPS="$PROV_IOPS"
  if [[ "$STORAGE_TYPE" == "gp3" ]] || [[ "$PROV_IOPS" -eq 0 ]]; then
    REF_IOPS="$(ceil_int "$NEED_IOPS")"
    [[ "$REF_IOPS" -lt 1 ]] && REF_IOPS=1
  fi
  if [[ "$REF_IOPS" -gt 0 ]]; then
    THRESH="$(awk -v p="$REF_IOPS" 'BEGIN { printf "%.6f", 10 * (p / 10000) }')"
    if awk -v d="$DQ_AVG" -v t="$THRESH" 'BEGIN { exit !(d > t) }'; then
      QUEUE_PRESSURE=1
    fi
  fi
fi

# Build notes array (newline-separated)
NOTES=""
append_note() {
  if [[ -z "$NOTES" ]]; then
    NOTES="$1"
  else
    NOTES="${NOTES}"$'\n'"$1"
  fi
}

if [[ "$FLAG_DLV_BLOCKER" -eq 1 ]]; then
  append_note "BLOCKER: Dedicated Log Volume is enabled — cannot use gp3 while DLV is on"
fi
if [[ "$STATUS" == "stopped" || "$EMPTY_METRICS" -eq 1 ]]; then
  append_note "Empty or stopped metrics — verify traffic before applying recommended settings"
fi
if [[ "$FLAG_OVER_MAX" -eq 1 ]]; then
  if [[ "$TARGET" == "gp3" ]]; then
    append_note "need_iops (${NEED_IOPS}) exceeds gp3 max (${GP3_MAX_IOPS}) — gp3 may not meet demand"
  else
    append_note "need_iops (${NEED_IOPS}) exceeds io2 methodology max (${IO2_MAX_IOPS})"
  fi
fi
if [[ "$FLAG_NEEDS_GROWTH" -eq 1 ]]; then
  append_note "Storage below stripe threshold or IOPS>size ratio — grow to ≥${STRIPE_THRESHOLD} GiB before tuning gp3, or stay on ${STORAGE_TYPE}"
fi
if [[ "$TIGHT_LATENCY" -eq 1 ]]; then
  append_note "p99 latency < 1 ms — confirm with the app owner whether a hard sub-ms SLA applies"
fi
if [[ "$QUEUE_PRESSURE" -eq 1 ]]; then
  append_note "DiskQueueDepth suggests I/O pressure — do not undersize the destination"
fi
if [[ "$RECOMMENDATION_OK" -eq 0 && "$FLAG_DLV_BLOCKER" -eq 0 && "$FLAG_NEEDS_GROWTH" -eq 0 && "$FLAG_OVER_MAX" -eq 0 ]]; then
  append_note "Recommendation incomplete — see notes above"
fi

MULTI_AZ_LABEL="No"
[[ "$MULTI_AZ" == "true" ]] && MULTI_AZ_LABEL="Yes"

CURRENT_COST_F="$(format_money "$CURRENT_COST")"
REC_COST_F="$(format_money "$REC_COST")"
COST_DELTA_F="$(format_money "$COST_DELTA")"

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

TF_TYPE_LINE="db_instance_storage_type       = \"${REC_STORAGE_TYPE}\""
TF_IOPS_LINE="db_instance_iops               = ${REC_IOPS_TF}"
TF_TP_LINE="db_instance_storage_throughput = ${REC_TP_TF}"

CURRENT_IOPS_DISP="$PROV_IOPS"
CURRENT_TP_DISP="n/a"
if [[ "$STORAGE_TYPE" == "gp3" ]]; then
  if [[ "$PROV_IOPS" == "0" || -z "$PROV_IOPS" ]]; then
    CURRENT_IOPS_DISP="baseline"
  fi
  if [[ "$STORAGE_TP" == "0" || -z "$STORAGE_TP" ]]; then
    CURRENT_TP_DISP="baseline"
  else
    CURRENT_TP_DISP="$STORAGE_TP"
  fi
fi

emit_notes() {
  if [[ -z "$NOTES" ]]; then
    echo "  (none)"
    return
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && echo "  - $line"
  done <<<"$NOTES"
}

emit_tf_block() {
  if [[ "$FLAG_DLV_BLOCKER" -eq 1 ]]; then
    cat <<EOF
  # No gp3 recommendation while Dedicated Log Volume is enabled
EOF
    return
  fi
  if [[ "$FLAG_NEEDS_GROWTH" -eq 1 && "$TARGET" == "gp3" && "$REC_IOPS_TF" == "null" ]]; then
    cat <<EOF
  # Grow allocated storage to ≥ ${STRIPE_THRESHOLD} GiB before tuning gp3, or keep ${STORAGE_TYPE}
  ${TF_TYPE_LINE}
  ${TF_IOPS_LINE}
  ${TF_TP_LINE}
EOF
    return
  fi
  cat <<EOF
  ${TF_TYPE_LINE}
  ${TF_IOPS_LINE}
  ${TF_TP_LINE}
EOF
}

emit_table() {
  cat <<EOF
=== RDS Storage Type Sizing ===
Instance: ${DB_INSTANCE} | Engine: ${ENGINE} | Region: ${REGION}
Direction: ${STORAGE_TYPE} → ${TARGET}

Current (${STORAGE_TYPE}):
  Storage: ${ALLOCATED} GiB | IOPS: ${CURRENT_IOPS_DISP} | Throughput: ${CURRENT_TP_DISP}
  Multi-AZ: ${MULTI_AZ_LABEL} | Instance class: ${INSTANCE_CLASS} | Status: ${STATUS}
  Estimated monthly cost: \$${CURRENT_COST_F}

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
  Demand (with headroom ${HEADROOM}): need_iops=$(disp_float "$NEED_IOPS" 0) need_tp=$(disp_float "$NEED_TP" 1) MiB/s

Recommended Terraform (${TARGET}):
$(emit_tf_block)

Estimated recommended monthly cost: \$${REC_COST_F}
Cost delta (current − recommended): ${COST_DELTA_PCT}% (\$${COST_DELTA_F}/mo)
  (positive = recommended is cheaper)

Notes:
$(emit_notes)
EOF
}

emit_markdown() {
  cat <<EOF
# RDS Storage Type Sizing

| Field | Value |
|-------|-------|
| Instance | \`${DB_INSTANCE}\` |
| Engine | \`${ENGINE}\` |
| Region | \`${REGION}\` |
| Direction | \`${STORAGE_TYPE}\` → \`${TARGET}\` |
| Current | \`${STORAGE_TYPE}\`, ${ALLOCATED} GiB, IOPS ${CURRENT_IOPS_DISP} |
| Multi-AZ | ${MULTI_AZ_LABEL} |
| Current cost | \$${CURRENT_COST_F}/mo |
| p99 TotalIOPS | $(disp_int "$TIOPS_P99") |
| Peak throughput | $(disp_float "$PEAK_TP_MIB" 1) MiB/s |
| Recommended IOPS | ${REC_IOPS_TF} |
| Recommended throughput | ${REC_TP_TF} |
| Recommended cost | \$${REC_COST_F}/mo |
| Cost delta | ${COST_DELTA_PCT}% (\$${COST_DELTA_F}/mo) |

\`\`\`hcl
${TF_TYPE_LINE}
${TF_IOPS_LINE}
${TF_TP_LINE}
\`\`\`

Notes:
$(emit_notes)
EOF
}

emit_json() {
  local notes_json
  if [[ -z "$NOTES" ]]; then
    notes_json='[]'
  else
    notes_json="$(printf '%s\n' "$NOTES" | jq -R . | jq -s .)"
  fi

  jq -nc \
    --arg instance "$DB_INSTANCE" \
    --arg engine "$ENGINE" \
    --arg region "$REGION" \
    --arg storage_type "$STORAGE_TYPE" \
    --arg target "$TARGET" \
    --argjson allocated "$ALLOCATED" \
    --argjson prov_iops "$PROV_IOPS" \
    --arg multi_az "$MULTI_AZ" \
    --arg instance_class "$INSTANCE_CLASS" \
    --arg status "$STATUS" \
    --argjson dlv "$DLV" \
    --argjson days "$DAYS" \
    --argjson period "$PERIOD" \
    --argjson current_cost "$CURRENT_COST" \
    --argjson recommended_cost "$REC_COST" \
    --argjson cost_delta "$COST_DELTA" \
    --argjson cost_delta_pct "$COST_DELTA_PCT" \
    --arg rec_iops_tf "$REC_IOPS_TF" \
    --arg rec_tp_tf "$REC_TP_TF" \
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
    --argjson recommendation_ok "$RECOMMENDATION_OK" \
    --argjson notes "$notes_json" \
    '{
      instance: $instance,
      engine: $engine,
      region: $region,
      direction: { from: $storage_type, to: $target },
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
        recommendation_ok: ($recommendation_ok == 1),
        db_instance_storage_type: $target,
        db_instance_iops: (if $rec_iops_tf == "null" then null else ($rec_iops_tf|tonumber) end),
        db_instance_storage_throughput: (if $rec_tp_tf == "null" then null else ($rec_tp_tf|tonumber) end)
      },
      cost: {
        current_monthly: $current_cost,
        recommended_monthly: $recommended_cost,
        delta_monthly: $cost_delta,
        delta_pct: $cost_delta_pct
      },
      notes: $notes
    }'
}

log "Done."

case "$FORMAT" in
  table) emit_table ;;
  markdown) emit_markdown ;;
  json) emit_json ;;
esac

exit 0
