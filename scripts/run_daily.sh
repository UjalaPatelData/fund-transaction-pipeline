#!/usr/bin/env bash
# Runs the daily order pipeline for one business date.
# Usage: ./scripts/run_daily.sh 2026-10-22
set -euo pipefail

BATCH_DATE="${1:-$(date +%F)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORDERS_FILE="$ROOT/data/orders_${BATCH_DATE}.csv"
NAV_FILE="$ROOT/data/nav_prices.csv"
LOG_DIR="$ROOT/logs"
LOG_FILE="$LOG_DIR/run_${BATCH_DATE}.log"

mkdir -p "$LOG_DIR"

if [[ ! -f "$ORDERS_FILE" ]]; then
  echo "$(date '+%F %T') ERROR: order file not found: $ORDERS_FILE" | tee -a "$LOG_FILE"
  exit 1
fi

echo "$(date '+%F %T') Starting batch $BATCH_DATE" | tee -a "$LOG_FILE"
python3 "$ROOT/etl/load_orders.py" \
  --orders "$ORDERS_FILE" \
  --nav "$NAV_FILE" \
  --date "$BATCH_DATE" \
  --report-dir "$ROOT/reports" 2>&1 | tee -a "$LOG_FILE"
echo "$(date '+%F %T') Finished batch $BATCH_DATE" | tee -a "$LOG_FILE"
