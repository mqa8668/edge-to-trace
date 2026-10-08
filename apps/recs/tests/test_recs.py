import asyncio
import io
import json
import logging

import httpx
import pytest
from fastapi.testclient import TestClient
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

from recs import main
from recs.chaos import Chaos, ChaosConfig, ChaosError, token_ok
from recs.ranking import rank

PRODUCTS = [{"id": i, "popularity": 100 - i} for i in range(1, 11)]


def catalog_transport():
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/products/popular":
            return httpx.Response(200, json={"products": PRODUCTS})
        if request.url.path == "/readyz":
            return httpx.Response(200, json={"status": "ready"})
        return httpx.Response(404)

    return httpx.MockTransport(handler)


def test_rank_excludes_viewed_and_orders_by_popularity():
    out = rank(1, PRODUCTS, limit=3)
    assert [c["id"] for c in out] == [2, 3, 4]


def test_recommendations_endpoint():
    with TestClient(main.create_app(Chaos(), catalog_transport())) as c:
        r = c.get("/recommendations", params={"product_id": 1})
        assert r.status_code == 200
        assert len(r.json()["recommendations"]) == 5
        assert c.get("/recommendations", params={"product_id": 0}).status_code == 422
        assert c.get("/healthz").status_code == 200
        assert c.get("/readyz").status_code == 200


def test_catalog_failure_is_502():
    t = httpx.MockTransport(lambda req: httpx.Response(500))
    with TestClient(main.create_app(Chaos(), t)) as c:
        assert c.get("/recommendations", params={"product_id": 1}).status_code == 502
        assert c.get("/readyz").status_code == 503


def test_chaos_error_injection():
    chaos = Chaos()
    chaos.set(ChaosConfig(error_ratio=1.0, ttl_seconds=30))
    with TestClient(main.create_app(chaos, catalog_transport())) as c:
        assert c.get("/recommendations", params={"product_id": 1}).status_code == 503
        assert c.get("/healthz").status_code == 200
        chaos.reset()
        assert c.get("/recommendations", params={"product_id": 1}).status_code == 200


def test_chaos_latency_sleeps_inside_span_and_marks_it():
    exporter = InMemorySpanExporter()
    provider = TracerProvider()
    provider.add_span_processor(SimpleSpanProcessor(exporter))
    trace.set_tracer_provider(provider)
    from recs import ranking

    ranking.tracer = provider.get_tracer("recs")
    asyncio.run(ranking.rank_candidates(1, PRODUCTS, chaos_delay=0.05))
    span = exporter.get_finished_spans()[0]
    assert span.name == "recs.rank_candidates"
    assert span.attributes["chaos.injected"] is True
    assert span.attributes["candidates.count"] == 10
    assert (span.end_time - span.start_time) >= 50_000_000  # ns


def test_chaos_ratios_ttl_and_validation():
    now = [0.0]
    rolls = iter([0.1, 0.9, 0.9, 0.1])
    c = Chaos(now=lambda: now[0], rnd=lambda: next(rolls))
    assert c.decide() == (0.0, False)  # inactive: consumes no rolls
    c.set(ChaosConfig(latency_ms=800, latency_ratio=0.6, error_ratio=0.25, ttl_seconds=60))
    assert c.decide() == (0.8, False)  # latency hit, error miss
    assert c.decide() == (0.0, True)  # latency miss, error hit
    now[0] = 61
    assert c.state()["active"] is False
    assert c.decide() == (0.0, False)
    for bad in (ChaosConfig(latency_ms=-1), ChaosConfig(latency_ratio=2), ChaosConfig(error_ratio=-1), ChaosConfig(ttl_seconds=3601)):
        with pytest.raises(ChaosError):
            c.set(bad)
    c.set(ChaosConfig(error_ratio=1))
    assert c.state()["config"]["ttl_seconds"] == 900


def test_admin_api_auth_and_roundtrip():
    chaos = Chaos()
    with TestClient(main.create_admin_app(chaos, "s3cret")) as c:
        assert c.get("/admin/chaos").status_code == 403
        h = {"X-Chaos-Token": "s3cret"}
        assert c.post("/admin/chaos", json={"error_ratio": 1, "ttl_seconds": 30}, headers=h).json()["active"] is True
        assert c.post("/admin/chaos", json={"latency_ratio": 5}, headers=h).status_code == 422
        assert c.post("/admin/chaos", json={"nope": 1}, headers=h).status_code == 400
        assert c.delete("/admin/chaos", headers=h).json()["active"] is False
    with TestClient(main.create_admin_app(chaos, "")) as c:
        assert c.get("/admin/chaos", headers={"X-Chaos-Token": ""}).status_code == 403
    assert not token_ok("", "")


def test_log_lines_are_json_with_trace_fields():
    from recs.logs import configure_logging

    configure_logging()
    buf = io.StringIO()
    logging.getLogger().handlers[0].setStream(buf)
    rec = logging.getLogger("recs").makeRecord("recs", logging.INFO, __file__, 1, "hello", (), None)
    rec.otelTraceID = "4bf92f3577b34da6a3ce929d0e0e4736"
    rec.otelSpanID = "00f067aa0ba902b7"
    logging.getLogger("recs").handle(rec)
    line = json.loads(buf.getvalue().strip().splitlines()[-1])
    assert line["msg"] == "hello" and line["service"] == "recs" and line["level"] == "INFO"
    assert line["trace_id"] == "4bf92f3577b34da6a3ce929d0e0e4736" and line["span_id"] == "00f067aa0ba902b7"
    assert line["ts"].endswith("Z") and "T" in line["ts"]
