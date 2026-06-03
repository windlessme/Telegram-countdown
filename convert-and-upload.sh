#!/bin/bash
set -euo pipefail

IMG="banner.jpg"
OUT="output.jpg"

for name in BOT_TOKEN CHAT_ID START_DATE TARGET_DATE; do
  if [ -z "${!name:-}" ]; then
    echo "ERROR: Missing required environment variable: $name"
    exit 1
  fi
done

if [ ! -f "$IMG" ]; then
  echo "ERROR: Missing banner image: $IMG"
  exit 1
fi

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

HEIGHT=$(identify -format "%h" "$IMG")
WIDTH=$(identify -format "%w" "$IMG")
COLOR_HEIGHT=$(( HEIGHT * PERCENT / 100 ))

if [ "$COLOR_HEIGHT" -le 0 ]; then
  convert "$IMG" -colorspace Gray "$OUT"
elif [ "$COLOR_HEIGHT" -ge "$HEIGHT" ]; then
  cp "$IMG" "$OUT"
else
  convert "$IMG" \
    -gravity North -crop "${WIDTH}x$(( HEIGHT - COLOR_HEIGHT ))+0+0" +repage \
    -colorspace Gray "top.jpg"

  convert "$IMG" \
    -gravity South -crop "${WIDTH}x${COLOR_HEIGHT}+0+0" +repage \
    "bottom.jpg"

  convert top.jpg bottom.jpg -append "$OUT"
fi

TITLE="${TITLE_PREFIX:-SITCON 2026 工人大群} | 倒數 $LEFT 天"

curl -fsS -X POST "https://api.telegram.org/bot$BOT_TOKEN/setChatTitle" \
  -d chat_id="$CHAT_ID" \
  -d title="$TITLE"

curl -fsS -X POST "https://api.telegram.org/bot$BOT_TOKEN/setChatPhoto" \
  -F chat_id="$CHAT_ID" \
  -F photo=@"$OUT"
