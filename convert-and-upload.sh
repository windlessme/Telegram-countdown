#!/bin/bash
set -euo pipefail

for name in BOT_TOKEN CHAT_ID START_DATE TARGET_DATE; do
  if [ -z "${!name:-}" ]; then
    echo "ERROR: Missing required environment variable: $name"
    exit 1
  fi
done

# Use the Asia/Taipei calendar date so manual runs calculate the same day count
# as the scheduled midnight run.
TODAY_DATE=$(TZ=Asia/Taipei date +%F)
TODAY_TIMESTAMP=$(date -d "$TODAY_DATE" +%s)
START_TIMESTAMP=$(date -d "$START_DATE" +%s)
TARGET_TIMESTAMP=$(date -d "$TARGET_DATE" +%s)

TOTAL=$(( (TARGET_TIMESTAMP - START_TIMESTAMP) / 86400 ))
LEFT=$(( (TARGET_TIMESTAMP - TODAY_TIMESTAMP) / 86400 ))
DAYS_DONE=$(( TOTAL - LEFT ))

if [ "$TOTAL" -le 0 ]; then
  echo "ERROR: Invalid date range"
  exit 1
fi

PERCENT=$(( 100 * DAYS_DONE / TOTAL ))
if [ "$PERCENT" -gt 100 ]; then PERCENT=100; fi
if [ "$PERCENT" -lt 0 ]; then PERCENT=0; fi

echo "Progress: $DAYS_DONE/$TOTAL days ($PERCENT%)"

TITLE="${TITLE_PREFIX:-SITCON Camp 2026} | ${LEFT} days left"

curl -fsS -X POST "https://api.telegram.org/bot$BOT_TOKEN/setChatTitle" \
  -d chat_id="$CHAT_ID" \
  -d title="$TITLE"
