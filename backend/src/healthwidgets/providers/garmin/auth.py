"""Garmin sign-in on top of python-garminconnect (>= 0.3).

The library handles the hard part (mobile SSO flow, Cloudflare-friendly TLS
impersonation, MFA, DI OAuth tokens with automatic refresh). This module only adapts
it to a stateless HTTP service:

* the password is used once and never stored, only the token JSON (``client.dumps()``)
  is kept, encrypted, by the caller;
* a pending MFA login is serialized (``client_state`` is JSON-serializable) so the code
  can be submitted in a later request, on any worker;
* library exceptions are mapped to provider-agnostic errors.
"""

from __future__ import annotations

import json
import logging
from collections.abc import Callable
from typing import Any

from garminconnect import (
    Garmin,
    GarminConnectAuthenticationError,
    GarminConnectConnectionError,
    GarminConnectTooManyRequestsError,
)

from ..base import (
    Account,
    InvalidCredentialsError,
    InvalidMfaCodeError,
    LoginNeedsMfa,
    LoginSuccess,
    ProviderAuthError,
    ProviderRateLimitedError,
    ProviderUnavailableError,
)

logger = logging.getLogger(__name__)


def start_login(email: str, password: str, *, is_cn: bool = False) -> LoginSuccess | LoginNeedsMfa:
    """Sign in with credentials. Returns the session, or a pending MFA challenge."""
    garmin = Garmin(email=email, password=password, is_cn=is_cn, return_on_mfa=True)
    status, client_state = _call(
        lambda: garmin.login(),
        on_auth=lambda exc: InvalidCredentialsError(
            "Garmin rejected these credentials (or the account is locked)."
        ),
    )
    if status == "needs_mfa":
        return LoginNeedsMfa(state=json.dumps(client_state), meta={"is_cn": is_cn})

    # With return_on_mfa=True the library returns before loading the profile, so
    # finish with a fresh instance restored from the tokens (no password kept around).
    return _session_from_tokens(garmin.client.dumps(), is_cn=is_cn)


def complete_mfa(state: str, code: str, *, is_cn: bool = False) -> LoginSuccess:
    """Finish a login that was waiting for the one-time code sent by Garmin."""
    garmin = Garmin(is_cn=is_cn)
    _call(
        lambda: garmin.resume_login(json.loads(state), code.strip()),
        on_auth=lambda exc: InvalidMfaCodeError("This verification code was not accepted."),
    )
    return LoginSuccess(account=_account(garmin, is_cn=is_cn), secret=garmin.client.dumps())


def restore_session(secret: str, *, is_cn: bool = False) -> Garmin:
    """Rebuild a ready-to-use client from stored tokens (refreshing them if needed)."""
    garmin = Garmin(is_cn=is_cn)
    _call(
        lambda: garmin.login(secret),
        on_auth=lambda exc: ProviderAuthError(
            "The Garmin session expired or was revoked. Please sign in again."
        ),
    )
    return garmin


def _session_from_tokens(tokens: str, *, is_cn: bool) -> LoginSuccess:
    if not json.loads(tokens).get("di_token"):
        # Only happens if Garmin fell back to a cookie-only web session, which the
        # library cannot serialize: it will work until the process restarts.
        logger.warning("Garmin returned a web-only session; it won't survive a restart")
    garmin = restore_session(tokens, is_cn=is_cn)
    return LoginSuccess(account=_account(garmin, is_cn=is_cn), secret=garmin.client.dumps())


def _account(garmin: Garmin, *, is_cn: bool) -> Account:
    profile_id = getattr(garmin, "profile_id", None)
    return Account(
        external_id=str(profile_id) if profile_id is not None else None,
        display_name=getattr(garmin, "display_name", None),
        full_name=getattr(garmin, "full_name", None) or None,
        meta={"is_cn": is_cn, "unit_system": getattr(garmin, "unit_system", None)},
    )


def _call[T](fn: Callable[[], T], *, on_auth: Callable[[Exception], Exception]) -> T:
    try:
        return fn()
    except GarminConnectAuthenticationError as exc:
        raise on_auth(exc) from exc
    except GarminConnectTooManyRequestsError as exc:
        raise ProviderRateLimitedError(
            "Garmin is rate limiting sign-ins from this server. Try again in a few minutes.",
            retry_after_seconds=600,
        ) from exc
    except GarminConnectConnectionError as exc:
        raise ProviderUnavailableError(f"Garmin Connect is unreachable: {exc}") from exc


def is_auth_error(exc: BaseException) -> bool:
    return isinstance(exc, GarminConnectAuthenticationError)


def is_rate_limit_error(exc: BaseException) -> bool:
    return isinstance(exc, GarminConnectTooManyRequestsError)


def describe(exc: BaseException) -> dict[str, Any]:
    """Small, log-safe description of a library exception."""
    response = getattr(exc, "response", None)
    return {"type": type(exc).__name__, "status": getattr(response, "status_code", None)}
