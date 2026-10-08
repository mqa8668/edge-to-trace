"""Runtime fault injection, toggled over the internal admin port."""

from __future__ import annotations

import hmac
import random
import time
from collections.abc import Callable
from dataclasses import asdict, dataclass

DEFAULT_TTL = 900
MAX_TTL = 3600


class ChaosError(ValueError):
    pass


@dataclass(frozen=True)
class ChaosConfig:
    latency_ms: int = 0
    latency_ratio: float = 0.0
    error_ratio: float = 0.0
    ttl_seconds: int = 0

    def validate(self) -> None:
        if not 0 <= self.latency_ms <= 60000:
            raise ChaosError("latency_ms must be between 0 and 60000")
        if not 0 <= self.latency_ratio <= 1:
            raise ChaosError("latency_ratio must be between 0 and 1")
        if not 0 <= self.error_ratio <= 1:
            raise ChaosError("error_ratio must be between 0 and 1")
        if not 0 <= self.ttl_seconds <= MAX_TTL:
            raise ChaosError("ttl_seconds must be between 0 and 3600")


class Chaos:
    def __init__(
        self,
        now: Callable[[], float] = time.monotonic,
        rnd: Callable[[], float] = random.random,
    ) -> None:
        self._now = now
        self._rnd = rnd
        self._cfg = ChaosConfig()
        self._expires: float | None = None

    def set(self, cfg: ChaosConfig) -> None:
        cfg.validate()
        ttl = cfg.ttl_seconds or DEFAULT_TTL
        self._cfg = ChaosConfig(cfg.latency_ms, cfg.latency_ratio, cfg.error_ratio, ttl)
        self._expires = self._now() + ttl

    def reset(self) -> None:
        self._cfg = ChaosConfig()
        self._expires = None

    def active(self) -> bool:
        return self._expires is not None and self._now() < self._expires

    def state(self) -> dict:
        if not self.active():
            return {"active": False, "config": asdict(ChaosConfig()), "remaining_seconds": 0}
        assert self._expires is not None
        return {
            "active": True,
            "config": asdict(self._cfg),
            "remaining_seconds": int(self._expires - self._now()),
        }

    def decide(self) -> tuple[float, bool]:
        """Return (delay_seconds, fail). Two independent rolls: latency, then error."""
        if not self.active():
            return 0.0, False
        delay = 0.0
        if self._cfg.latency_ms > 0 and self._rnd() < self._cfg.latency_ratio:
            delay = self._cfg.latency_ms / 1000
        fail = self._cfg.error_ratio > 0 and self._rnd() < self._cfg.error_ratio
        return delay, fail


def token_ok(expected: str, got: str | None) -> bool:
    """An empty configured token disables the admin API entirely."""
    return bool(expected) and got is not None and hmac.compare_digest(expected.encode(), got.encode())
