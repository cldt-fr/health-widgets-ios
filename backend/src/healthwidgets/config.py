"""Runtime configuration, read from environment variables prefixed with ``HW_``."""

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="HW_", env_file=".env", extra="ignore")

    # Where the SQLite database (and the generated encryption key, if any) live.
    data_dir: Path = Path("./data")

    # Fernet key(s) used to encrypt provider tokens and cached snapshots at rest.
    # Comma-separated to rotate keys: the first one encrypts, all of them decrypt.
    # When empty, a key is generated once into ``data_dir/secret.key`` (mode 0600).
    encryption_key: str | None = None

    # Code the app must send to register a new device, so that only you can use your
    # server. When empty, one is generated on first start (``data_dir/signup-code``) and
    # printed in the logs.
    signup_code: str | None = None
    # Skip the signup code entirely (local development only).
    open_registration: bool = False

    # Snapshot freshness. Each provider endpoint also has its own TTL (sleep and
    # HRV change once a day, steps every few minutes), see providers/garmin/fetch.py.
    snapshot_ttl_seconds: int = 300
    # Minimum delay between two forced refreshes for the same user, to protect
    # the Garmin account from rate limiting when the app or a widget insists.
    min_force_refresh_seconds: int = 60

    # Parallel Garmin calls per snapshot.
    garmin_max_workers: int = 6
    # Seconds to wait for a single Garmin endpoint before giving up on it.
    garmin_call_timeout_seconds: float = 25.0
    # Login attempts allowed per user in a 15-minute window (Garmin locks
    # accounts that fail too many times).
    max_login_attempts: int = 5

    # Expose a synthetic "demo" provider (App Review, UI work, end-to-end tests).
    enable_demo_provider: bool = False

    # App Store review account. Signing in to Garmin with exactly this email and password
    # connects a sample account served by the demo data, without calling Garmin, so that
    # App Review can go through the real sign-in flow. Disabled unless both are set.
    review_email: str | None = None
    review_password: str | None = None

    # Privacy policy served at /privacy (link it from the App Store listing): who runs
    # this server, how to reach them, and where it is hosted.
    privacy_operator: str | None = None
    privacy_contact: str | None = None
    privacy_hosting: str | None = None

    log_level: str = "INFO"

    @property
    def database_path(self) -> Path:
        return self.data_dir / "healthwidgets.sqlite3"


@lru_cache
def get_settings() -> Settings:
    return Settings()
