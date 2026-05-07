# auth2api Integration Design

**Date:** 2026-05-07  
**Status:** Approved

## Goal

Add [auth2api](https://github.com/AmazingAng/auth2api) as a sidecar service so that new-api can route AI requests through the user's Claude Max and ChatGPT Plus web subscriptions instead of (or alongside) direct API keys.

## Architecture

```
Client → new-api → [Claude Max channel]    → auth2api:8317/v1/messages          → Anthropic (via OAuth token)
                   [ChatGPT Plus channel]  → auth2api:8317/v1/chat/completions   → OpenAI (via OAuth token)
```

auth2api is a TypeScript/Node.js standalone proxy that holds OAuth web tokens for Claude and ChatGPT and exposes an OpenAI-compatible HTTP API. new-api treats it as any other upstream provider via its existing channel adapter system — no Go code changes required.

## New Files

| Path | Purpose |
|---|---|
| `auth2api/Dockerfile` | Multi-stage build: clones auth2api from GitHub at build time, compiles TypeScript |
| `auth2api/entrypoint.sh` | Runs `envsubst` to inject `AUTH2API_KEY` into config template, then starts auth2api |
| `auth2api/config.tmpl.yaml` | auth2api config template (`host`, `port`, `auth-dir`, `api-keys`) |
| `scripts/init-channels.sh` | One-shot shell script: logs into new-api admin API via session cookie, seeds Claude Max and ChatGPT Plus channels if not already present |

## Modified Files

| Path | Change |
|---|---|
| `docker-compose.yml` | Add `auth2api` service, `channel-init` one-shot service, `auth2api_data` named volume |
| `.env` | User adds `AUTH2API_KEY=<secret>` and `NEW_API_ADMIN_PASSWORD=<root-password>` |

## docker-compose Changes

### auth2api service

- Build context: `./auth2api`
- Named volume `auth2api_data` mounted at `/data` (persists OAuth tokens across restarts)
- `config.tmpl.yaml` mounted read-only at `/config/config.tmpl.yaml`
- Internal network only — not exposed on host
- Healthcheck: `GET http://localhost:8317/health`
- auth2api listens on `0.0.0.0:8317` (set via config template so Docker networking works)

### channel-init service

- Image: `alpine` with `curl` and `jq` installed
- `restart: "no"` — runs once and exits
- `depends_on`: new-api (condition: `service_healthy`), auth2api (condition: `service_healthy`)
- Environment: `NEW_API_URL`, `NEW_API_ADMIN_PASSWORD`, `AUTH2API_KEY`, `AUTH2API_URL`
- Mounts `./scripts/init-channels.sh` and executes it

### New volume

```yaml
volumes:
  auth2api_data:
```

## Channel Seeding (init-channels.sh)

1. POST `/api/user/login` with `{"username":"root","password":"$NEW_API_ADMIN_PASSWORD"}` — save session cookie
2. GET `/api/channel` — extract list of existing channel names
3. If "Claude Max" not present: POST `/api/channel` with:
   - `type: 14` (Anthropic)
   - `base_url: http://auth2api:8317`
   - `key: $AUTH2API_KEY`
   - `models: claude-opus-4-7,claude-sonnet-4-6,claude-haiku-4-5`
4. If "ChatGPT Plus" not present: POST `/api/channel` with:
   - `type: 1` (OpenAI)
   - `base_url: http://auth2api:8317`
   - `key: $AUTH2API_KEY`
   - `models: gpt-4o,gpt-4o-mini,o1,o1-mini,o3-mini`
5. Exit 0 in all cases (idempotent)

## Adapter Compatibility

No Go changes needed. Existing adapters work because:

- **Anthropic adapter (type 14):** sends `x-api-key: $AUTH2API_KEY` + Anthropic-format body to `/v1/messages` — auth2api accepts both header formats and Anthropic native format.
- **OpenAI adapter (type 1):** sends `Authorization: Bearer $AUTH2API_KEY` + OpenAI-format body to `/v1/chat/completions` — auth2api accepts this natively.

auth2api routes upstream based on model name prefix (`claude-*` → Anthropic, `gpt-*`/`o*` → OpenAI), so model names must be kept consistent between new-api channel model lists and auth2api's routing rules.

## One-Time Auth Setup

After `docker compose up -d`, the user must authenticate each subscription once. OAuth tokens are then persisted in `auth2api_data` volume:

```sh
# Claude Max
docker compose exec auth2api node dist/index.js --login --manual

# ChatGPT Plus (if desired) — exact provider flag to be confirmed from auth2api README
docker compose exec auth2api node dist/index.js --login --manual [--provider openai]
```

auth2api prints an OAuth URL; the user completes the flow in their browser and pastes the callback URL back into the terminal.

## .env Additions

```env
AUTH2API_KEY=<chosen-secret-key>
NEW_API_ADMIN_PASSWORD=<root-user-password>
```

`NEW_API_ADMIN_PASSWORD` defaults to `123456` (new-api's hardcoded default for the root user on first install). Users who have changed it must set this correctly.

## Out of Scope

- New Go channel types for auth2api (channels appear as "Anthropic" and "OpenAI" type in the UI — labels are set by the channel name field)
- Automatic token refresh UI in new-api admin
- Cursor provider support (auth2api supports it; can be added later by creating a third channel)
- Multi-account failover configuration (auth2api handles this internally)
