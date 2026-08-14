"""Responsibility: load and persist resumable cleanup state.

Safety boundary: rejects tenancy mismatches and serializes updates under a lock.
Cleanup sequence role: records decisions and actions across the full cleanup sequence.

``Manifest.load`` initializes or validates tenancy-bound JSON state. Thread-safe
``record_action`` and ``record_error`` updates make concurrent region work resumable,
while ``completed`` prevents successful mutations from being repeated.
"""

from __future__ import annotations

import json
import pathlib
import threading
from dataclasses import dataclass, field
from typing import Any, Optional

from .errors import CleanupError
from .resources import utc_now

@dataclass
class Manifest:
    path: pathlib.Path
    tenancy_id: str
    data: dict[str, Any] = field(default_factory=dict)
    lock: threading.RLock = field(
        default_factory=threading.RLock,
        init=False,
        repr=False,
    )

    @classmethod
    def load(cls, path: pathlib.Path, tenancy_id: str) -> "Manifest":
        if path.exists():
            with path.open(encoding="utf-8") as handle:
                data = json.load(handle)
            if data.get("tenancy_id") != tenancy_id:
                raise CleanupError(
                    f"Manifest tenancy {data.get('tenancy_id')} does not match "
                    f"{tenancy_id}"
                )
        else:
            data = {
                "version": 1,
                "tenancy_id": tenancy_id,
                "created_at": utc_now(),
                "updated_at": utc_now(),
                "context": {},
                "resources": [],
                "actions": {},
                "errors": [],
            }
        return cls(path=path, tenancy_id=tenancy_id, data=data)

    def save(self) -> None:
        with self.lock:
            self.data["updated_at"] = utc_now()
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.path.with_suffix(self.path.suffix + ".tmp")
            with temporary.open("w", encoding="utf-8") as handle:
                json.dump(self.data, handle, indent=2, sort_keys=True)
                handle.write("\n")
            temporary.replace(self.path)

    def completed(self, action_id: str) -> bool:
        with self.lock:
            return (
                self.data["actions"].get(action_id, {}).get("status")
                == "completed"
            )

    def record_action(
        self,
        action_id: str,
        description: str,
        status: str,
        **details: Any,
    ) -> None:
        with self.lock:
            self.data["actions"][action_id] = {
                "description": description,
                "status": status,
                "updated_at": utc_now(),
                **details,
            }

    def record_error(
        self,
        message: str,
        action_id: Optional[str] = None,
        raw_error: Optional[str] = None,
    ) -> None:
        with self.lock:
            error = {"message": message, "time": utc_now()}
            if action_id:
                error["action_id"] = action_id
            if raw_error and raw_error != message:
                error["raw_error"] = raw_error
            self.data["errors"].append(error)

