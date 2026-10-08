from __future__ import annotations

import asyncio
import logging
import os
import time
from contextlib import asynccontextmanager

import httpx
import uvicorn
from fastapi import FastAPI, Header, HTTPException, Query, Request
from fastapi.responses import JSONResponse

from .chaos import Chaos, ChaosConfig, ChaosError, token_ok
from .logs import configure_logging
from .ranking import rank_candidates

configure_logging()
log = logging.getLogger("recs")

CATALOG_URL = os.environ.get("CATALOG_URL", "http://catalog:8081")
CHAOS_TOKEN = os.environ.get("CHAOS_TOKEN", "")
HEALTH_PATHS = {"/healthz", "/readyz"}


def create_app(
    chaos: Chaos | None = None,
    transport: httpx.AsyncBaseTransport | None = None,
    admin_app: FastAPI | None = None,
) -> FastAPI:
    chaos = chaos or Chaos()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.http = httpx.AsyncClient(base_url=CATALOG_URL, timeout=2.0, transport=transport)
        admin_server = admin_task = None
        if admin_app is not None:
            # Admin API on a second, internal-only port, in the same process so it shares the chaos state.
            cfg = uvicorn.Config(admin_app, host="0.0.0.0", port=int(os.environ.get("ADMIN_PORT", "9000")),
                                 log_config=None, access_log=False)
            admin_server = uvicorn.Server(cfg)
            admin_server.install_signal_handlers = lambda: None  # the main server owns signals
            admin_task = asyncio.create_task(admin_server.serve())
        yield
        if admin_server is not None and admin_task is not None:
            admin_server.should_exit = True
            await admin_task
        await app.state.http.aclose()

    app = FastAPI(title="recs", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
    app.state.chaos = chaos

    @app.middleware("http")
    async def access_log(request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        if request.url.path not in HEALTH_PATHS:
            log.info(
                "request",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status": response.status_code,
                    "duration_ms": round((time.perf_counter() - start) * 1000, 2),
                },
            )
        return response

    @app.get("/healthz")
    async def healthz():
        return {"status": "ok"}

    @app.get("/readyz")
    async def readyz(request: Request):
        try:
            r = await request.app.state.http.get("/readyz")
            r.raise_for_status()
        except httpx.HTTPError:
            return JSONResponse({"status": "catalog unavailable"}, status_code=503)
        return {"status": "ready"}

    @app.get("/recommendations")
    async def recommendations(request: Request, product_id: int = Query(ge=1), limit: int = Query(5, ge=1, le=20)):
        delay, fail = chaos.decide()
        if fail:
            log.warning("chaos: injected failure")
            return JSONResponse({"error": "chaos: injected failure"}, status_code=503)
        try:
            r = await request.app.state.http.get("/products/popular", params={"limit": 20})
            r.raise_for_status()
        except httpx.HTTPError as exc:
            log.error("catalog call failed", extra={"error": str(exc)})
            return JSONResponse({"error": "catalog unavailable"}, status_code=502)
        ranked = await rank_candidates(product_id, r.json()["products"], delay, limit)
        return {"product_id": product_id, "recommendations": ranked}

    return app


def create_admin_app(chaos: Chaos, token: str) -> FastAPI:
    admin = FastAPI(title="recs-admin", docs_url=None, redoc_url=None, openapi_url=None)

    def check(x_chaos_token: str | None) -> None:
        if not token_ok(token, x_chaos_token):
            raise HTTPException(status_code=403, detail="forbidden")

    @admin.get("/admin/chaos")
    async def get_chaos(x_chaos_token: str | None = Header(None)):
        check(x_chaos_token)
        return chaos.state()

    @admin.post("/admin/chaos")
    async def set_chaos(body: dict, x_chaos_token: str | None = Header(None)):
        check(x_chaos_token)
        allowed = {"latency_ms", "latency_ratio", "error_ratio", "ttl_seconds"}
        if set(body) - allowed:
            raise HTTPException(status_code=400, detail="unknown field")
        try:
            chaos.set(ChaosConfig(**body))
        except (ChaosError, TypeError) as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc
        return chaos.state()

    @admin.delete("/admin/chaos")
    async def reset_chaos(x_chaos_token: str | None = Header(None)):
        check(x_chaos_token)
        chaos.reset()
        return chaos.state()

    return admin


_chaos = Chaos()
app = create_app(_chaos, admin_app=create_admin_app(_chaos, CHAOS_TOKEN))
