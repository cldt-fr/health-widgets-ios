"""Device tokens and encryption at rest."""

from __future__ import annotations

import hashlib
import hmac
import logging
import os
import secrets
from pathlib import Path

from cryptography.fernet import Fernet, InvalidToken, MultiFernet

logger = logging.getLogger(__name__)

TOKEN_PREFIX = "hw_"


def new_device_token() -> str:
    """Return a new opaque bearer token for a device (never stored in clear)."""
    return TOKEN_PREFIX + secrets.token_urlsafe(32)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def constant_time_equals(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode("utf-8"), b.encode("utf-8"))


class DecryptionError(Exception):
    """Raised when a stored secret can't be decrypted (wrong or rotated-out key)."""


class Vault:
    """Symmetric encryption for provider tokens, MFA states and cached snapshots."""

    def __init__(self, keys: list[bytes]) -> None:
        if not keys:
            raise ValueError("At least one encryption key is required")
        self._fernet = MultiFernet([Fernet(key) for key in keys])

    def encrypt(self, plaintext: str) -> bytes:
        return self._fernet.encrypt(plaintext.encode("utf-8"))

    def decrypt(self, token: bytes) -> str:
        try:
            return self._fernet.decrypt(token).decode("utf-8")
        except InvalidToken as exc:
            raise DecryptionError("Stored secret could not be decrypted") from exc


SIGNUP_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"  # no 0/o/1/l/i: easy to type on a phone


def resolve_signup_code(
    configured: str | None, data_dir: Path, *, open_registration: bool
) -> str | None:
    """The code required to register a device: configured, or generated once and kept."""
    if open_registration:
        return None
    if configured and configured.strip():
        return configured.strip()
    code_file = data_dir / "signup-code"
    if code_file.exists():
        return code_file.read_text().strip()
    data_dir.mkdir(parents=True, exist_ok=True)
    raw = "".join(secrets.choice(SIGNUP_ALPHABET) for _ in range(12))
    code = "-".join(raw[i : i + 4] for i in range(0, 12, 4))
    fd = os.open(code_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(code + "\n")
    return code


def load_vault(configured_keys: str | None, data_dir: Path) -> Vault:
    """Build the vault from ``HW_ENCRYPTION_KEY`` or a key file generated on first run."""
    if configured_keys:
        keys = [k.strip().encode("ascii") for k in configured_keys.split(",") if k.strip()]
        return Vault(keys)

    key_file = data_dir / "secret.key"
    if key_file.exists():
        return Vault([key_file.read_bytes().strip()])

    data_dir.mkdir(parents=True, exist_ok=True)
    key = Fernet.generate_key()
    fd = os.open(key_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(key)
    logger.info(
        "Generated an encryption key in %s: keep it with your backups (without it, "
        "users have to reconnect their provider).",
        key_file,
    )
    return Vault([key])
