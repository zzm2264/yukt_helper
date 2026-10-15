"""Thread-safe, atomic JSON persistence store for Course Helper API Server.

Guarantees data integrity during concurrent requests through thread locks (RLock)
and atomic file replacements (write to .tmp then os.replace).
"""

from __future__ import annotations

import json
import os
import threading
from pathlib import Path
from typing import Any, Callable, TypeVar

T = TypeVar("T")


class JsonStoreError(Exception):
    """Raised when JSON persistence operation fails."""
    pass


# Default storage directory: ./data under server folder or custom YKT_DATA_DIR
DATA_DIR = Path(os.environ.get("YKT_DATA_DIR", Path(__file__).resolve().parent / "data"))
DATA_DIR.mkdir(parents=True, exist_ok=True)


def data_path(filename: str) -> Path:
    """Resolve absolute path inside storage data directory."""
    return DATA_DIR / filename


class SafeJsonStore:
    """Thread-safe JSON file store with atomic file swapping."""

    def __init__(self, filename: str | Path, default_factory: Callable[[], Any] = dict):
        self.path = data_path(str(filename)) if not isinstance(filename, Path) else filename
        self.default_factory = default_factory
        self.lock = threading.RLock()
        self._ensure_exists()

    def _ensure_exists(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            with self.lock:
                if not self.path.exists():
                    self._write_unlocked(self.default_factory())

    def _read_unlocked(self) -> Any:
        if not self.path.exists():
            return self.default_factory()
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                content = f.read().strip()
                if not content:
                    return self.default_factory()
                return json.loads(content)
        except Exception as exc:
            raise JsonStoreError(f"Failed to read JSON from {self.path}: {exc}") from exc

    def _write_unlocked(self, data: Any) -> None:
        tmp_path = self.path.with_suffix(".tmp")
        try:
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_path, self.path)
        except Exception as exc:
            if tmp_path.exists():
                try:
                    tmp_path.unlink()
                except OSError:
                    pass
            raise JsonStoreError(f"Failed to write JSON atomically to {self.path}: {exc}") from exc

    def read(self) -> Any:
        """Safely read the entire JSON data."""
        with self.lock:
            return self._read_unlocked()

    def update(self, mutator: Callable[[Any], T]) -> T:
        """Atomically read, mutate and save data within an exclusive lock."""
        with self.lock:
            data = self._read_unlocked()
            result = mutator(data)
            self._write_unlocked(data)
            return result


# Pre-configured stores required by api_server
ACCOUNTS_STORE = SafeJsonStore("accounts.json", list)
AI_HEALTH_STORE = SafeJsonStore("ai_health.json", dict)
HISTORY_STORE = SafeJsonStore("history.json", list)
KEYS_STORE = SafeJsonStore("keys.json", dict)
PROBLEM_STATE_STORE = SafeJsonStore("problem_states.json", dict)
