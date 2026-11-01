"""SQLite persistence (users, device tokens, provider connections, MFA challenges, snapshots).

SQLite in WAL mode is plenty for a self-hosted sync server. One connection is shared
across threads and every access is serialized with a lock, which keeps things simple
and correct (Garmin calls, not the database, are the slow part).
"""

from __future__ import annotations

import json
import sqlite3
import threading
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id          TEXT PRIMARY KEY,
    created_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
    token_hash    TEXT PRIMARY KEY,
    user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name          TEXT,
    created_at    TEXT NOT NULL,
    last_seen_at  TEXT
);

CREATE TABLE IF NOT EXISTS connections (
    user_id          TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider         TEXT NOT NULL,
    status           TEXT NOT NULL,
    external_id      TEXT,
    display_name     TEXT,
    full_name        TEXT,
    secret           BLOB,
    meta             TEXT NOT NULL DEFAULT '{}',
    created_at       TEXT NOT NULL,
    updated_at       TEXT NOT NULL,
    last_success_at  TEXT,
    last_error       TEXT,
    PRIMARY KEY (user_id, provider)
);

CREATE TABLE IF NOT EXISTS challenges (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider    TEXT NOT NULL,
    secret      BLOB NOT NULL,
    meta        TEXT NOT NULL DEFAULT '{}',
    attempts    INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL,
    expires_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS login_attempts (
    user_id     TEXT NOT NULL,
    provider    TEXT NOT NULL,
    at          TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS login_attempts_by_user ON login_attempts(user_id, provider, at);

CREATE TABLE IF NOT EXISTS snapshots (
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day         TEXT NOT NULL,
    payload     BLOB NOT NULL,
    fetched_at  TEXT NOT NULL,
    PRIMARY KEY (user_id, day)
);
"""


def utcnow() -> datetime:
    return datetime.now(UTC).replace(microsecond=0)


def _iso(value: datetime | None) -> str | None:
    return value.astimezone(UTC).isoformat() if value else None


def _parse(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value) if value else None


@dataclass(slots=True)
class Connection:
    user_id: str
    provider: str
    status: str
    external_id: str | None
    display_name: str | None
    full_name: str | None
    secret: bytes | None
    meta: dict[str, Any]
    created_at: datetime
    updated_at: datetime
    last_success_at: datetime | None
    last_error: str | None


@dataclass(slots=True)
class Challenge:
    id: str
    user_id: str
    provider: str
    secret: bytes
    meta: dict[str, Any]
    attempts: int
    created_at: datetime
    expires_at: datetime


class Database:
    def __init__(self, path: Path | str) -> None:
        if str(path) != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(path), check_same_thread=False, isolation_level=None)
        self._conn.row_factory = sqlite3.Row
        self._lock = threading.RLock()
        with self._lock:
            self._conn.execute("PRAGMA journal_mode=WAL")
            self._conn.execute("PRAGMA foreign_keys=ON")
            self._conn.executescript(SCHEMA)

    def close(self) -> None:
        with self._lock:
            self._conn.close()

    @contextmanager
    def _tx(self) -> Iterator[sqlite3.Connection]:
        with self._lock:
            self._conn.execute("BEGIN IMMEDIATE")
            try:
                yield self._conn
            except BaseException:
                self._conn.execute("ROLLBACK")
                raise
            else:
                self._conn.execute("COMMIT")

    def _one(self, sql: str, params: tuple[Any, ...]) -> sqlite3.Row | None:
        with self._lock:
            return self._conn.execute(sql, params).fetchone()

    def _all(self, sql: str, params: tuple[Any, ...]) -> list[sqlite3.Row]:
        with self._lock:
            return self._conn.execute(sql, params).fetchall()

    # -- users & devices ---------------------------------------------------------------

    def create_user_with_device(self, token_hash: str, device_name: str | None) -> str:
        user_id = str(uuid.uuid4())
        now = _iso(utcnow())
        with self._tx() as conn:
            conn.execute("INSERT INTO users (id, created_at) VALUES (?, ?)", (user_id, now))
            conn.execute(
                "INSERT INTO devices (token_hash, user_id, name, created_at, last_seen_at) "
                "VALUES (?, ?, ?, ?, ?)",
                (token_hash, user_id, device_name, now, now),
            )
        return user_id

    def user_for_token(self, token_hash: str) -> str | None:
        row = self._one("SELECT user_id FROM devices WHERE token_hash = ?", (token_hash,))
        if row is None:
            return None
        with self._tx() as conn:
            conn.execute(
                "UPDATE devices SET last_seen_at = ? WHERE token_hash = ?",
                (_iso(utcnow()), token_hash),
            )
        return str(row["user_id"])

    def delete_user(self, user_id: str) -> None:
        with self._tx() as conn:
            conn.execute("DELETE FROM login_attempts WHERE user_id = ?", (user_id,))
            conn.execute("DELETE FROM users WHERE id = ?", (user_id,))

    # -- provider connections ----------------------------------------------------------

    def upsert_connection(
        self,
        user_id: str,
        provider: str,
        *,
        status: str,
        secret: bytes | None,
        external_id: str | None,
        display_name: str | None,
        full_name: str | None,
        meta: dict[str, Any],
    ) -> None:
        now = _iso(utcnow())
        with self._tx() as conn:
            conn.execute(
                """
                INSERT INTO connections (user_id, provider, status, external_id, display_name,
                    full_name, secret, meta, created_at, updated_at, last_success_at, last_error)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                ON CONFLICT (user_id, provider) DO UPDATE SET
                    status = excluded.status, external_id = excluded.external_id,
                    display_name = excluded.display_name, full_name = excluded.full_name,
                    secret = excluded.secret, meta = excluded.meta,
                    updated_at = excluded.updated_at, last_success_at = excluded.last_success_at,
                    last_error = NULL
                """,
                (
                    user_id,
                    provider,
                    status,
                    external_id,
                    display_name,
                    full_name,
                    secret,
                    json.dumps(meta),
                    now,
                    now,
                    now,
                ),
            )

    def get_connection(self, user_id: str, provider: str) -> Connection | None:
        row = self._one(
            "SELECT * FROM connections WHERE user_id = ? AND provider = ?", (user_id, provider)
        )
        return self._connection(row) if row else None

    def list_connections(self, user_id: str) -> list[Connection]:
        rows = self._all(
            "SELECT * FROM connections WHERE user_id = ? ORDER BY created_at", (user_id,)
        )
        return [self._connection(row) for row in rows]

    def update_connection_secret(self, user_id: str, provider: str, secret: bytes) -> None:
        with self._tx() as conn:
            conn.execute(
                "UPDATE connections SET secret = ?, updated_at = ? "
                "WHERE user_id = ? AND provider = ?",
                (secret, _iso(utcnow()), user_id, provider),
            )

    def mark_connection_success(self, user_id: str, provider: str) -> None:
        now = _iso(utcnow())
        with self._tx() as conn:
            conn.execute(
                "UPDATE connections SET status = 'connected', last_success_at = ?, "
                "last_error = NULL WHERE user_id = ? AND provider = ?",
                (now, user_id, provider),
            )

    def mark_connection_error(
        self, user_id: str, provider: str, error: str, *, status: str | None = None
    ) -> None:
        with self._tx() as conn:
            if status:
                conn.execute(
                    "UPDATE connections SET status = ?, last_error = ?, updated_at = ? "
                    "WHERE user_id = ? AND provider = ?",
                    (status, error[:500], _iso(utcnow()), user_id, provider),
                )
            else:
                conn.execute(
                    "UPDATE connections SET last_error = ? WHERE user_id = ? AND provider = ?",
                    (error[:500], user_id, provider),
                )

    def delete_connection(self, user_id: str, provider: str) -> bool:
        with self._tx() as conn:
            cursor = conn.execute(
                "DELETE FROM connections WHERE user_id = ? AND provider = ?", (user_id, provider)
            )
            conn.execute("DELETE FROM snapshots WHERE user_id = ?", (user_id,))
            return cursor.rowcount > 0

    @staticmethod
    def _connection(row: sqlite3.Row) -> Connection:
        return Connection(
            user_id=row["user_id"],
            provider=row["provider"],
            status=row["status"],
            external_id=row["external_id"],
            display_name=row["display_name"],
            full_name=row["full_name"],
            secret=row["secret"],
            meta=json.loads(row["meta"] or "{}"),
            created_at=_parse(row["created_at"]) or utcnow(),
            updated_at=_parse(row["updated_at"]) or utcnow(),
            last_success_at=_parse(row["last_success_at"]),
            last_error=row["last_error"],
        )

    # -- MFA challenges ----------------------------------------------------------------

    def create_challenge(
        self,
        user_id: str,
        provider: str,
        secret: bytes,
        meta: dict[str, Any],
        expires_at: datetime,
    ) -> str:
        challenge_id = str(uuid.uuid4())
        with self._tx() as conn:
            # One pending challenge per user and provider.
            conn.execute(
                "DELETE FROM challenges WHERE user_id = ? AND provider = ?", (user_id, provider)
            )
            conn.execute(
                "INSERT INTO challenges (id, user_id, provider, secret, meta, attempts, "
                "created_at, expires_at) VALUES (?, ?, ?, ?, ?, 0, ?, ?)",
                (
                    challenge_id,
                    user_id,
                    provider,
                    secret,
                    json.dumps(meta),
                    _iso(utcnow()),
                    _iso(expires_at),
                ),
            )
        return challenge_id

    def get_challenge(self, challenge_id: str, user_id: str) -> Challenge | None:
        row = self._one(
            "SELECT * FROM challenges WHERE id = ? AND user_id = ?", (challenge_id, user_id)
        )
        if row is None:
            return None
        return Challenge(
            id=row["id"],
            user_id=row["user_id"],
            provider=row["provider"],
            secret=row["secret"],
            meta=json.loads(row["meta"] or "{}"),
            attempts=row["attempts"],
            created_at=_parse(row["created_at"]) or utcnow(),
            expires_at=_parse(row["expires_at"]) or utcnow(),
        )

    def increment_challenge_attempts(self, challenge_id: str) -> None:
        with self._tx() as conn:
            conn.execute(
                "UPDATE challenges SET attempts = attempts + 1 WHERE id = ?", (challenge_id,)
            )

    def delete_challenge(self, challenge_id: str) -> None:
        with self._tx() as conn:
            conn.execute("DELETE FROM challenges WHERE id = ?", (challenge_id,))

    def purge_expired_challenges(self) -> None:
        with self._tx() as conn:
            conn.execute("DELETE FROM challenges WHERE expires_at < ?", (_iso(utcnow()),))

    # -- login rate limiting -----------------------------------------------------------

    def record_login_attempt(self, user_id: str, provider: str) -> None:
        with self._tx() as conn:
            conn.execute(
                "INSERT INTO login_attempts (user_id, provider, at) VALUES (?, ?, ?)",
                (user_id, provider, _iso(utcnow())),
            )

    def purge_login_attempts(self, before: datetime) -> None:
        with self._tx() as conn:
            conn.execute("DELETE FROM login_attempts WHERE at < ?", (_iso(before),))

    def count_login_attempts_since(self, user_id: str, provider: str, since: datetime) -> int:
        row = self._one(
            "SELECT COUNT(*) AS n FROM login_attempts WHERE user_id = ? AND provider = ? "
            "AND at >= ?",
            (user_id, provider, _iso(since)),
        )
        return int(row["n"]) if row else 0

    # -- snapshots ---------------------------------------------------------------------

    def save_snapshot(self, user_id: str, day: str, payload: bytes) -> None:
        with self._tx() as conn:
            conn.execute(
                "INSERT INTO snapshots (user_id, day, payload, fetched_at) VALUES (?, ?, ?, ?) "
                "ON CONFLICT (user_id, day) DO UPDATE SET payload = excluded.payload, "
                "fetched_at = excluded.fetched_at",
                (user_id, day, payload, _iso(utcnow())),
            )
            # Only the last couple of weeks are useful as a stale fallback.
            conn.execute(
                "DELETE FROM snapshots WHERE user_id = ? AND day NOT IN "
                "(SELECT day FROM snapshots WHERE user_id = ? ORDER BY day DESC LIMIT 14)",
                (user_id, user_id),
            )

    def get_latest_snapshot(self, user_id: str) -> tuple[bytes, datetime] | None:
        row = self._one(
            "SELECT payload, fetched_at FROM snapshots WHERE user_id = ? ORDER BY day DESC LIMIT 1",
            (user_id,),
        )
        if row is None:
            return None
        return bytes(row["payload"]), _parse(row["fetched_at"]) or utcnow()

    def get_snapshot(self, user_id: str, day: str) -> tuple[bytes, datetime] | None:
        row = self._one(
            "SELECT payload, fetched_at FROM snapshots WHERE user_id = ? AND day = ?",
            (user_id, day),
        )
        if row is None:
            return None
        return bytes(row["payload"]), _parse(row["fetched_at"]) or utcnow()
