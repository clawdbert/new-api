#!/bin/sh
envsubst '$AUTH2API_KEY' < /config/config.tmpl.yaml > /app/config.yaml
node dist/index.js "$@"
echo "[auth2api] Process exited (no accounts yet or restart needed)."
echo "[auth2api] Authenticate with:"
echo "[auth2api]   docker compose exec auth2api node dist/index.js --login --manual"
echo "[auth2api] Then restart: docker compose restart auth2api"
tail -f /dev/null
