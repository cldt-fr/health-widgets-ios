"""HTTP API consumed by the iOS app and its widgets.

No ``from __future__ import annotations`` here: FastAPI must resolve the locally defined
``User`` dependency alias at runtime.
"""

import logging
from datetime import date
from typing import Annotated

from fastapi import Depends, FastAPI, Query, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from . import __version__
from .config import Settings, get_settings
from .db import Database
from .privacy import render_privacy_policy
from .schemas import (
    ConnectResponse,
    DashboardSnapshot,
    ErrorBody,
    ErrorResponse,
    GarminConnectRequest,
    MeResponse,
    MfaRequest,
    ProviderId,
    RegisterDeviceRequest,
    RegisterDeviceResponse,
)
from .security import load_vault, resolve_signup_code
from .service import HealthService, ServiceError

logger = logging.getLogger("healthwidgets")

bearer = HTTPBearer(auto_error=False)

ERRORS = {
    401: {"model": ErrorResponse},
    429: {"model": ErrorResponse},
    502: {"model": ErrorResponse},
}


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    logging.basicConfig(
        level=settings.log_level.upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    # python-garminconnect is chatty at INFO and can echo request details at DEBUG.
    logging.getLogger("garminconnect").setLevel(logging.WARNING)

    db = Database(settings.database_path)
    vault = load_vault(settings.encryption_key, settings.data_dir)
    signup_code = resolve_signup_code(
        settings.signup_code, settings.data_dir, open_registration=settings.open_registration
    )
    service = HealthService(settings, db, vault, signup_code)
    if signup_code:
        logger.info("Signup code (enter it in the app): %s", signup_code)
    else:
        logger.warning("Open registration: anyone reaching this server can use it")

    app = FastAPI(
        title="Health Widgets sync server",
        version=__version__,
        description="Normalized health & training snapshots for the Health Widgets iOS app.",
    )
    app.state.service = service

    @app.exception_handler(ServiceError)
    async def service_error_handler(_: Request, exc: ServiceError) -> JSONResponse:
        headers = {"Retry-After": str(exc.retry_after_seconds)} if exc.retry_after_seconds else None
        body = ErrorResponse(
            error=ErrorBody(
                code=exc.code, message=exc.message, retry_after_seconds=exc.retry_after_seconds
            )
        )
        return JSONResponse(
            status_code=exc.status,
            content=body.model_dump(by_alias=True, exclude_none=True),
            headers=headers,
        )

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
        first = exc.errors()[0] if exc.errors() else {}
        where = ".".join(str(part) for part in first.get("loc", []) if part != "body")
        body = ErrorResponse(
            error=ErrorBody(
                code="invalid_request", message=f"{where}: {first.get('msg', 'invalid')}"
            )
        )
        return JSONResponse(
            status_code=422, content=body.model_dump(by_alias=True, exclude_none=True)
        )

    def current_user(
        credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    ) -> str:
        user_id = service.authenticate(credentials.credentials) if credentials else None
        if user_id is None:
            raise ServiceError(401, "invalid_token", "Unknown or revoked device token.")
        return user_id

    User = Annotated[str, Depends(current_user)]

    # Snapshots are ~15 KB of JSON: ~4x smaller compressed, which matters on cellular.
    app.add_middleware(GZipMiddleware, minimum_size=1024)

    @app.get("/health", tags=["meta"])
    def health() -> dict[str, str]:
        return {"status": "ok", "version": __version__}

    privacy_page = render_privacy_policy(settings)

    @app.get("/privacy", include_in_schema=False)
    def privacy() -> HTMLResponse:
        return HTMLResponse(privacy_page)

    @app.post(
        "/v1/devices", response_model=RegisterDeviceResponse, tags=["devices"], status_code=201
    )
    def register_device(body: RegisterDeviceRequest) -> RegisterDeviceResponse:
        """Create an account for a new install and return its device token."""
        return service.register_device(body.name, body.signup_code)

    @app.get("/v1/me", response_model=MeResponse, tags=["account"], responses=ERRORS)
    def me(user_id: User) -> MeResponse:
        return service.me(user_id)

    @app.delete("/v1/me", status_code=204, tags=["account"])
    def delete_me(user_id: User) -> Response:
        """Delete the account, its provider tokens and cached data."""
        service.delete_account(user_id)
        return Response(status_code=204)

    @app.post(
        "/v1/connections/garmin",
        response_model=ConnectResponse,
        response_model_exclude_none=True,
        tags=["connections"],
        responses=ERRORS,
    )
    def connect_garmin(body: GarminConnectRequest, user_id: User) -> ConnectResponse:
        """Sign in to Garmin Connect. The password is used once and never stored.

        Returns ``mfa_required`` with a ``challengeId`` when Garmin sent a one-time code.
        """
        return service.connect_garmin(user_id, body)

    @app.post(
        "/v1/connections/garmin/mfa",
        response_model=ConnectResponse,
        response_model_exclude_none=True,
        tags=["connections"],
        responses=ERRORS,
    )
    def garmin_mfa(body: MfaRequest, user_id: User) -> ConnectResponse:
        return service.submit_garmin_mfa(user_id, body)

    @app.post(
        "/v1/connections/demo",
        response_model=ConnectResponse,
        response_model_exclude_none=True,
        tags=["connections"],
    )
    def connect_demo(user_id: User) -> ConnectResponse:
        return service.connect_demo(user_id)

    @app.delete("/v1/connections/{provider}", status_code=204, tags=["connections"])
    def disconnect(provider: ProviderId, user_id: User) -> Response:
        service.disconnect(user_id, provider)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @app.get("/v1/snapshot", response_model=DashboardSnapshot, tags=["data"], responses=ERRORS)
    def snapshot(
        user_id: User,
        day: Annotated[
            date | None, Query(alias="date", description="Local day, YYYY-MM-DD")
        ] = None,
        refresh: Annotated[bool, Query(description="Bypass caches for live metrics")] = False,
    ) -> DashboardSnapshot:
        """Everything the dashboard and the widgets display, for one calendar day."""
        return service.snapshot(user_id, day, force=refresh)

    return app
