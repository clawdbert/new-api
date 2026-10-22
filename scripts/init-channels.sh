#!/bin/sh
set -e

NEW_API_URL="${NEW_API_URL:-http://new-api:3000}"
ADMIN_PASSWORD="${NEW_API_ADMIN_PASSWORD:-123456}"
AUTH2API_KEY="${AUTH2API_KEY:?AUTH2API_KEY must be set}"
AUTH2API_URL="${AUTH2API_URL:-http://auth2api:8317}"

COOKIE_JAR=$(mktemp)
trap 'rm -f "$COOKIE_JAR"' EXIT

echo "[init] Logging in to new-api..."
LOGIN_RESP=$(curl -sf -c "$COOKIE_JAR" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"root\",\"password\":\"${ADMIN_PASSWORD}\"}" \
  "${NEW_API_URL}/api/user/login")

SUCCESS=$(printf '%s' "$LOGIN_RESP" | jq -r '.success')
if [ "$SUCCESS" != "true" ]; then
  echo "[init] Login failed: $LOGIN_RESP"
  exit 1
fi

USER_ID=$(printf '%s' "$LOGIN_RESP" | jq -r '.data.user.id')
ACCESS_TOKEN=$(printf '%s' "$LOGIN_RESP" | jq -r '.data.access_token')
if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  echo "[init] Login response carried no access_token: $LOGIN_RESP"
  exit 1
fi
echo "[init] Login OK (user id=$USER_ID)."

echo "[init] Fetching existing channels..."
EXISTING=$(curl -sf -b "$COOKIE_JAR" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "New-Api-User: ${USER_ID}" \
  "${NEW_API_URL}/api/channel/?p=1&page_size=100")
NAMES=$(printf '%s' "$EXISTING" | jq -r '.data.items[].name' 2>/dev/null || true)

create_channel() {
  local name="$1" type="$2" models="$3"
  if printf '%s\n' "$NAMES" | grep -qx "$name"; then
    echo "[init] '$name' already exists — skipping."
    return
  fi
  echo "[init] Creating '$name'..."
  RESULT=$(curl -sf -b "$COOKIE_JAR" -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "New-Api-User: ${USER_ID}" \
    -d "{
      \"mode\": \"single\",
      \"channel\": {
        \"name\": \"${name}\",
        \"type\": ${type},
        \"key\": \"${AUTH2API_KEY}\",
        \"base_url\": \"${AUTH2API_URL}\",
        \"models\": \"${models}\",
        \"status\": 1,
        \"group\": \"default\"
      }
    }" \
    "${NEW_API_URL}/api/channel/")
  echo "[init] Result: $RESULT"
}

create_channel "Claude Max" 14 \
  "claude-opus-4-7,claude-sonnet-4-6,claude-haiku-4-5,claude-3-5-sonnet-20241022,claude-3-5-haiku-20241022,claude-3-opus-20240229"

create_channel "ChatGPT Plus" 1 \
  "gpt-4o,gpt-4o-mini,o1,o1-mini,o3-mini,gpt-4-turbo,gpt-4"

echo "[init] Done."
