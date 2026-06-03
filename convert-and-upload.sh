#!/bin/bash
set -euo pipefail

OUT="output.jpg"
TELEGRAM_SOURCE_IMG="telegram-chat-photo.jpg"

for name in BOT_TOKEN CHAT_ID START_DATE TARGET_DATE; do
  if [ -z "${!name:-}" ]; then
    echo "ERROR: Missing required environment variable: $name"
    exit 1
  fi
done

download_current_chat_photo() {
  echo "Downloading current Telegram chat photo..."

  local chat_json
  local photo_file_id
  local file_json
  local file_path

  chat_json=$(curl -fsS -G "https://api.telegram.org/bot$BOT_TOKEN/getChat" \
    --data-urlencode "chat_id=$CHAT_ID")

  photo_file_id=$(printf '%s' "$chat_json" | jq -r '.result.photo.big_file_id // .result.photo.small_file_id // empty')
  if [ -z "$photo_file_id" ]; then
    echo "ERROR: Telegram chat has no current photo. Add avatar.jpg or banner.jpg to the repo."
    exit 1
  fi

  file_json=$(curl -fsS -G "https://api.telegram.org/bot$BOT_TOKEN/getFile" \
    --data-urlencode "file_id=$photo_file_id")
  file_path=$(printf '%s' "$file_json" | jq -r '.result.file_path // empty')
  if [ -z "$file_path" ]; then
    echo "ERROR: Could not resolve Telegram chat photo file path."
    exit 1
  fi

  curl -fsS "https://api.telegram.org/file/bot$BOT_TOKEN/$file_path" \
    -o "$TELEGRAM_SOURCE_IMG"
}

if [ "${USE_TELEGRAM_CHAT_PHOTO:-false}" = "true" ]; then
  download_current_chat_photo
  SOURCE_IMG="$TELEGRAM_SOURCE_IMG"
elif [ -n "${SOURCE_IMAGE:-}" ]; then
  SOURCE_IMG="$SOURCE_IMAGE"
elif [ -f "avatar.jpg" ]; then
  SOURCE_IMG="avatar.jpg"
elif [ -f "banner.jpg" ]; then
  SOURCE_IMG="banner.jpg"
elif [ "${FALLBACK_TO_TELEGRAM_CHAT_PHOTO:-true}" = "true" ]; then
  download_current_chat_photo
  SOURCE_IMG="$TELEGRAM_SOURCE_IMG"
else
  echo "ERROR: No source image found. Add avatar.jpg or banner.jpg to the repo."
  exit 1
fi

if [ ! -f "$SOURCE_IMG" ]; then
  echo "ERROR: Missing source image: $SOURCE_IMG"
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
echo "Source image: $SOURCE_IMG"

# Telegram group photos are square. Start from the source image, center-crop it
# to a square, then generate a grayscale-to-color progress reveal.
convert "$SOURCE_IMG" \
  -auto-orient \
  -resize 512x512^ \
  -gravity center \
  -extent 512x512 \
  "source-square.jpg"

WIDTH=$(identify -format "%w" "source-square.jpg")
HEIGHT=$(identify -format "%h" "source-square.jpg")
COLOR_HEIGHT=$(( HEIGHT * PERCENT / 100 ))
REVEAL_TOP=$(( HEIGHT - COLOR_HEIGHT ))
FEATHER=$(( HEIGHT / 16 ))
if [ "$FEATHER" -lt 16 ]; then FEATHER=16; fi

if [ "$COLOR_HEIGHT" -le 0 ]; then
  convert "source-square.jpg" -colorspace Gray "$OUT"
elif [ "$COLOR_HEIGHT" -ge "$HEIGHT" ]; then
  cp "source-square.jpg" "$OUT"
else
  convert "source-square.jpg" -colorspace Gray "gray.jpg"
  convert -size "${WIDTH}x${HEIGHT}" xc:black \
    -fill white \
    -draw "rectangle 0,${REVEAL_TOP} ${WIDTH},${HEIGHT}" \
    -blur "0x${FEATHER}" \
    "mask.png"
  convert "source-square.jpg" "mask.png" \
    -alpha off \
    -compose CopyOpacity \
    -composite \
    "color-layer.png"
  convert "gray.jpg" "color-layer.png" \
    -compose Over \
    -composite \
    "$OUT"
fi

TITLE="${TITLE_PREFIX:-SITCON 2026 Countdown} | ${LEFT} days left"

curl -fsS -X POST "https://api.telegram.org/bot$BOT_TOKEN/setChatTitle" \
  -d chat_id="$CHAT_ID" \
  -d title="$TITLE"

curl -fsS -X POST "https://api.telegram.org/bot$BOT_TOKEN/setChatPhoto" \
  -F chat_id="$CHAT_ID" \
  -F photo=@"$OUT"
