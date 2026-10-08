from __future__ import annotations

import logging
import sys
from datetime import UTC, datetime

from pythonjsonlogger.json import JsonFormatter

SERVICE = "recs"


class Formatter(JsonFormatter):
    def formatTime(self, record: logging.LogRecord, datefmt: str | None = None) -> str:
        return datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")

    def process_log_record(self, log_data: dict) -> dict:
        for key in ("otelServiceName", "otelTraceSampled"):
            log_data.pop(key, None)
        return super().process_log_record(log_data)


def configure_logging() -> None:
    """One JSON object per line on stdout: ts, level, msg, service, trace_id, span_id.

    trace_id/span_id come from the OTel logging instrumentation (OTEL_PYTHON_LOG_CORRELATION=true),
    which sets otelTraceID/otelSpanID on every record ("0" outside a span).
    """
    fmt = Formatter(
        "%(asctime)s %(levelname)s %(message)s %(otelTraceID)s %(otelSpanID)s",
        rename_fields={
            "asctime": "ts",
            "levelname": "level",
            "message": "msg",
            "otelTraceID": "trace_id",
            "otelSpanID": "span_id",
        },
        static_fields={"service": SERVICE},
        defaults={"otelTraceID": "", "otelSpanID": ""},
    )
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(fmt)
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        lg = logging.getLogger(name)
        lg.handlers = []
        lg.propagate = True
    logging.getLogger("uvicorn.access").disabled = True  # replaced by the request middleware below
    logging.getLogger("httpx").setLevel(logging.WARNING)
