from __future__ import annotations

import asyncio
import hashlib

from opentelemetry import trace

tracer = trace.get_tracer("recs")


def _tiebreak(product_id: int, candidate_id: int) -> int:
    digest = hashlib.sha256(f"{product_id}:{candidate_id}".encode()).digest()
    return digest[0]


def rank(product_id: int, candidates: list[dict], limit: int = 5) -> list[dict]:
    """Pure ranking: drop the viewed product, order by popularity with a stable per-product tiebreak."""
    pool = [c for c in candidates if c.get("id") != product_id]
    pool.sort(key=lambda c: (-c.get("popularity", 0), _tiebreak(product_id, c["id"])))
    return pool[:limit]


async def rank_candidates(product_id: int, candidates: list[dict], chaos_delay: float = 0.0, limit: int = 5) -> list[dict]:
    """Ranking wrapped in a manual span. Injected latency sleeps *inside* the span so the trace points here."""
    with tracer.start_as_current_span("recs.rank_candidates") as span:
        span.set_attribute("candidates.count", len(candidates))
        span.set_attribute("chaos.injected", chaos_delay > 0)
        if chaos_delay > 0:
            await asyncio.sleep(chaos_delay)
        return rank(product_id, candidates, limit)
