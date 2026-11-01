# Health Widgets server

A small FastAPI service that connects to sports-watch providers (Garmin for now, through
[python-garminconnect](https://github.com/cyberjunky/python-garminconnect)) and serves a
**normalized, provider-agnostic snapshot** of the day to the Health Widgets iOS app and
its widgets.

## Run it

```bash
docker compose up -d
docker compose logs api | grep "Signup code"   # the code to type in the app
```

That's it: no configuration is required. On first start the server generates an
encryption key and a signup code, and keeps both in the `health-widgets-data` volume
(back it up with your other data).

Without Docker (Python 3.12+ and [uv](https://docs.astral.sh/uv/)):

```bash
uv sync
uv run healthwidgets-server            # add --reload while developing
```

## Configuration

Optional: copy `.env.example` to `.env`, then `docker compose up -d` again.

| Variable | Default | Purpose |
|---|---|---|
| `HW_PORT` | `8000` | Port published by Docker Compose |
| `HW_SIGNUP_CODE` | generated | Code required to register a device |
| `HW_OPEN_REGISTRATION` | `false` | Skip the signup code (local development only) |
| `HW_ENCRYPTION_KEY` | generated | Fernet key(s) encrypting tokens at rest. Comma-separated to rotate: the first encrypts, all decrypt |
| `HW_DATA_DIR` | `./data` (`/data` in Docker) | SQLite database, generated key and code |
| `HW_SNAPSHOT_TTL_SECONDS` | `300` | Freshness of live metrics (steps, heart rate, stress, Body Battery) |
| `HW_MIN_FORCE_REFRESH_SECONDS` | `60` | Minimum delay between two forced refreshes |
| `HW_GARMIN_MAX_WORKERS` | `6` | Parallel Garmin calls per snapshot |
| `HW_GARMIN_CALL_TIMEOUT_SECONDS` | `25` | Time budget for the Garmin calls of one snapshot |
| `HW_MAX_LOGIN_ATTEMPTS` | `5` | Sign-in attempts per 15 minutes (Garmin locks accounts that fail repeatedly) |
| `HW_ENABLE_DEMO_PROVIDER` | `false` | Synthetic "demo" provider for UI work and testing |
| `HW_LOG_LEVEL` | `INFO` | |

Machine-specific tweaks, such as joining a reverse-proxy network, binding to `127.0.0.1` or
using a bind mount, go in a `docker-compose.override.yml` next to `docker-compose.yml`.
Docker Compose merges it automatically, and it is git-ignored.

## How data stays fresh without hammering Garmin

Each Garmin endpoint has its own freshness budget. Steps, heart rate, stress and Body
Battery are refetched every 5 minutes. Sleep and HRV are refetched every hour, or every
10–15 minutes until the morning sync has arrived. Planned workouts (Garmin calendar and
Garmin Coach, through Garmin's GraphQL API) are refetched every 30 minutes, race predictions
every 6 hours, and the heart-rate zones of a finished activity are cached for 30 days. The server only calls Garmin when the app or a widget asks, runs the calls in
parallel, and caches the raw payloads.

When Garmin can't be reached, or the session has expired, `/v1/snapshot` returns the last
good snapshot flagged `stale: true` (and `needsReauth: true`) instead of an error, so
widgets keep showing something.

## Security

- The Garmin password is used once, to obtain OAuth tokens, and is never stored. The
  library refreshes the tokens automatically, and every rotation is persisted.
- Garmin tokens, pending MFA logins and cached snapshots are encrypted at rest (Fernet).
- Each app install gets a random device token. Only its SHA-256 hash is stored.
- `DELETE /v1/me` removes the account, its tokens and its cached data.
- Expose the server over HTTPS if it is reachable from the internet: health data should not
  travel in clear text.

## API

Every `/v1` route except device registration expects `Authorization: Bearer <device token>`.
Errors look like `{"error": {"code", "message", "retryAfterSeconds"?}}`. Interactive docs
are at `/docs`.

| Method | Route | Description |
|---|---|---|
| `POST` | `/v1/devices` | Register an install → `{token, userId}` |
| `GET` | `/v1/me` | Connected providers and their status |
| `DELETE` | `/v1/me` | Delete the account and all its data |
| `POST` | `/v1/connections/garmin` | `{email, password, isCn}` → `connected`, or `mfa_required` with a `challengeId` |
| `POST` | `/v1/connections/garmin/mfa` | `{challengeId, code}` → `connected` |
| `POST` | `/v1/connections/demo` | Connect the demo provider (if enabled) |
| `DELETE` | `/v1/connections/{provider}` | Disconnect a provider |
| `GET` | `/v1/snapshot?date=YYYY-MM-DD&refresh=false` | The day's snapshot |

Notable error codes: `provider_reauth_required` (401, sign in to Garmin again),
`invalid_credentials`, `invalid_mfa_code`, `provider_rate_limited` (429),
`no_provider_connected` (409), `invalid_token` (401, unknown device token),
`invalid_signup_code` (403).

## Deploying to a remote machine

`deploy.sh` copies the sources over SSH, rebuilds the image and restarts the container.
The remote `.env`, `data/` and `docker-compose.override.yml` are never touched:

```bash
DEPLOY_HOST=user@my-server DEPLOY_DIR=/opt/health-widgets ./deploy.sh
```

The two variables can also go in a git-ignored `.deploy.env` file.

## Tests

```bash
uv run pytest
uv run ruff check .
```

The normalizer tests use synthetic Garmin payloads whose shapes mirror real responses,
quirks included: four timestamp encodings, `-1`/`-2` sentinels, descriptor arrays.

## Adding a provider

1. Create `src/healthwidgets/providers/<name>/` with the sign-in flow (OAuth,
   credentials…) and a normalizer that returns `schemas.DashboardSnapshot`.
2. Register it in `service.py` (`_active_connection`, connection routes in `main.py`).
3. On iOS, set `ProviderID.<name>.isAvailable` to `true`.
