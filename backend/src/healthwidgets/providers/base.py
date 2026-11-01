"""What every watch provider (Garmin today; Polar, Coros, Suunto... later) must implement."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Any, Protocol

from ..schemas import DashboardSnapshot


class ProviderError(Exception):
    """Base class for provider failures surfaced to the API layer."""

    code = "provider_error"


class ProviderAuthError(ProviderError):
    """The stored session is no longer valid: the user has to sign in again."""

    code = "provider_reauth_required"


class InvalidCredentialsError(ProviderError):
    code = "invalid_credentials"


class InvalidMfaCodeError(ProviderError):
    code = "invalid_mfa_code"


class ProviderRateLimitedError(ProviderError):
    code = "provider_rate_limited"

    def __init__(self, message: str, retry_after_seconds: int = 300) -> None:
        super().__init__(message)
        self.retry_after_seconds = retry_after_seconds


class ProviderUnavailableError(ProviderError):
    code = "provider_unavailable"


@dataclass(slots=True)
class Account:
    """Identity of the provider account, used for display and de-duplication."""

    external_id: str | None
    display_name: str | None
    full_name: str | None
    meta: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class LoginSuccess:
    account: Account
    secret: str  # serialized session (tokens), encrypted before storage


@dataclass(slots=True)
class LoginNeedsMfa:
    state: str  # serialized pending login, encrypted before storage
    meta: dict[str, Any] = field(default_factory=dict)


class SnapshotProvider(Protocol):
    """A connected account able to produce a normalized snapshot for a calendar day."""

    def fetch_snapshot(self, day: date, *, force: bool) -> DashboardSnapshot: ...
