#!/bin/sh
set -e
envsubst '$AUTH2API_KEY' < /config/config.tmpl.yaml > /app/config.yaml
exec node dist/index.js "$@"
