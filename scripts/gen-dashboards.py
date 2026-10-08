#!/usr/bin/env python3
"""Generate the Grafana dashboards in grafana/dashboards/ (dashboards as code).

Run `make dashboards` after editing. The JSON files are committed; CI regenerates them and fails on drift.
Only the standard library is used.
"""
import json
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "grafana", "dashboards")

PROM = {"type": "prometheus", "uid": "prometheus"}
LOKI = {"type": "loki", "uid": "loki"}
TEMPO = {"type": "tempo", "uid": "tempo"}

GREEN, YELLOW, ORANGE, RED, BLUE, GREY = "green", "yellow", "orange", "red", "blue", "#6b7280"

SERVER = 'span_kind="SPAN_KIND_SERVER"'
CALLS = "traces_span_metrics_calls_total"
BUCKET = "traces_span_metrics_duration_milliseconds_bucket"


class Board:
    def __init__(self, uid, title, description, tags=None, variables=None, refresh="10s", frm="now-30m"):
        self.uid, self.title, self.description = uid, title, description
        self.tags = ["edge-to-trace"] + (tags or [])
        self.variables = variables or []
        self.refresh, self.frm = refresh, frm
        self.panels = []
        self._id = 0
        self._y = 0
        self._x = 0
        self._rowh = 0

    def _next_id(self):
        self._id += 1
        return self._id

    def row(self, title):
        self._wrap()
        self.panels.append({"type": "row", "id": self._next_id(), "title": title, "collapsed": False,
                            "gridPos": {"h": 1, "w": 24, "x": 0, "y": self._y}, "panels": []})
        self._y += 1

    def _wrap(self):
        if self._x:
            self._y += self._rowh
            self._x, self._rowh = 0, 0

    def add(self, panel, w, h):
        if self._x + w > 24:
            self._wrap()
        panel["id"] = self._next_id()
        panel["gridPos"] = {"h": h, "w": w, "x": self._x, "y": self._y}
        self.panels.append(panel)
        self._x += w
        self._rowh = max(self._rowh, h)

    def json(self):
        self._wrap()
        return {
            "uid": self.uid,
            "title": self.title,
            "description": self.description,
            "tags": self.tags,
            "schemaVersion": 41,
            "version": 1,
            "editable": False,
            "graphTooltip": 1,
            "refresh": self.refresh,
            "time": {"from": self.frm, "to": "now"},
            "timepicker": {"refresh_intervals": ["5s", "10s", "30s", "1m"]},
            "templating": {"list": self.variables},
            "annotations": {"list": [
                {"builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"}, "enable": True,
                 "hide": True, "iconColor": "rgba(0, 211, 255, 1)", "name": "Annotations and alerts", "type": "dashboard"},
                {"datasource": {"type": "grafana", "uid": "-- Grafana --"}, "enable": True, "iconColor": "orange",
                 "name": "Chaos injected", "target": {"type": "tags", "tags": ["chaos"], "limit": 100, "matchAny": False}},
            ]},
            "links": [
                {"title": "Platform overview", "type": "link", "url": "/d/e2t-overview", "icon": "dashboard"},
                {"title": "SLO detail", "type": "link", "url": "/d/e2t-slo", "icon": "dashboard"},
                {"title": "Service drill-down", "type": "link", "url": "/d/e2t-service", "icon": "dashboard"},
                {"title": "Beyla / eBPF", "type": "link", "url": "/d/e2t-beyla", "icon": "dashboard"},
            ],
            "panels": self.panels,
        }


def steps(*pairs):
    """steps((None, GREEN), (95, YELLOW)) -> threshold steps."""
    return {"mode": "absolute", "steps": [{"color": c, "value": v} for v, c in pairs]}


def prom(expr, legend="", ref="A", instant=False, exemplar=False, hide=False):
    q = {"refId": ref, "datasource": PROM, "expr": expr, "legendFormat": legend, "range": not instant, "instant": instant}
    if exemplar:
        q["exemplar"] = True
    if hide:
        q["hide"] = True
    return q


def stat(title, targets, unit, thresholds, desc="", mappings=None, decimals=None, color_mode="background", graph="none"):
    defaults = {"unit": unit, "thresholds": thresholds, "color": {"mode": "thresholds"}, "mappings": mappings or []}
    if decimals is not None:
        defaults["decimals"] = decimals
    return {"type": "stat", "title": title, "description": desc, "datasource": PROM, "targets": targets,
            "fieldConfig": {"defaults": defaults, "overrides": []},
            "options": {"colorMode": color_mode, "graphMode": graph, "textMode": "value", "reduceOptions": {"calcs": ["lastNotNull"]},
                        "justifyMode": "center"}}


def gauge(title, targets, unit, thresholds, desc="", vmin=0, vmax=100):
    return {"type": "gauge", "title": title, "description": desc, "datasource": PROM, "targets": targets,
            "fieldConfig": {"defaults": {"unit": unit, "min": vmin, "max": vmax, "thresholds": thresholds, "color": {"mode": "thresholds"}}, "overrides": []},
            "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "showThresholdMarkers": True}}


def ts(title, targets, unit, desc="", thresholds=None, stack=False, ds=PROM, vmin=None, vmax=None, overrides=None, fill=12, thr_style="dashed", soft_max=None):
    defaults = {"unit": unit, "custom": {"lineWidth": 2, "fillOpacity": fill, "showPoints": "never", "spanNulls": True,
                                         "stacking": {"mode": "normal" if stack else "none"},
                                         "thresholdsStyle": {"mode": thr_style if thresholds else "off"}},
                "color": {"mode": "palette-classic"}}
    if soft_max is not None:
        defaults["custom"]["axisSoftMax"] = soft_max
    if thresholds:
        defaults["thresholds"] = thresholds
    if vmin is not None:
        defaults["min"] = vmin
    if vmax is not None:
        defaults["max"] = vmax
    return {"type": "timeseries", "title": title, "description": desc, "datasource": ds, "targets": targets,
            "fieldConfig": {"defaults": defaults, "overrides": overrides or []},
            "options": {"legend": {"displayMode": "table", "placement": "bottom", "calcs": ["lastNotNull"]},
                        "tooltip": {"mode": "multi", "sort": "desc"}}}


def logs(title, expr, desc=""):
    return {"type": "logs", "title": title, "description": desc, "datasource": LOKI,
            "targets": [{"refId": "A", "datasource": LOKI, "expr": expr, "queryType": "range", "maxLines": 200}],
            "options": {"showTime": True, "wrapLogMessage": True, "enableLogDetails": True, "prettifyLogMessage": False,
                        "sortOrder": "Descending", "dedupStrategy": "none"}}


def table(title, targets, desc="", overrides=None, ds=PROM, transformations=None):
    return {"type": "table", "title": title, "description": desc, "datasource": ds, "targets": targets,
            "fieldConfig": {"defaults": {"custom": {"align": "auto"}}, "overrides": overrides or []},
            "options": {"showHeader": True, "cellHeight": "sm"}, "transformations": transformations or []}


def text(title, md):
    return {"type": "text", "title": title, "options": {"mode": "markdown", "content": md}, "transparent": True}


def var_query(name, label, query, include_all=False, current=None, multi=False):
    v = {"name": name, "label": label, "type": "query", "datasource": PROM,
         "query": {"query": query, "qryType": 1, "refId": "v"}, "refresh": 2, "sort": 1,
         "includeAll": include_all, "multi": multi}
    if include_all:
        v["allValue"] = ".*"
    if current:
        v["current"] = {"text": current, "value": current}
    return v


def var_custom(name, label, options, current):
    return {"name": name, "label": label, "type": "custom", "query": ",".join(options),
            "options": [{"text": o, "value": o, "selected": o == current} for o in options],
            "current": {"text": current, "value": current}}


def rate_by(group, extra="", window="1m"):
    sel = f"{SERVER}{(',' + extra) if extra else ''}"
    return f"sum by ({group}) (rate({CALLS}{{{sel}}}[{window}]))"


def err_ratio(group, extra="", window="1m"):
    sel = f"{SERVER}{(',' + extra) if extra else ''}"
    total = f'sum by ({group}) (rate({CALLS}{{{sel}}}[{window}]))'
    errors = f'sum by ({group}) (rate({CALLS}{{{sel},status_code="STATUS_CODE_ERROR"}}[{window}]))'
    # "or 0 * total" keeps the series at zero while nothing fails, so panels do not go empty.
    return f'(({errors} or 0 * {total}) / {total})'


def quantile(q, group, extra="", window="1m"):
    sel = f"{SERVER}{(',' + extra) if extra else ''}"
    return f"histogram_quantile({q}, sum by (le{(', ' + group) if group else ''}) (rate({BUCKET}{{{sel}}}[{window}])))"


def alert_state_mappings():
    return [{"type": "value", "options": {"0": {"text": "OK", "color": GREEN}}},
            {"type": "range", "options": {"from": 1, "to": 1000, "result": {"text": "PAGING", "color": RED}}}]


# --------------------------------------------------------------------------- overview
def overview():
    b = Board("e2t-overview", "Platform overview",
              "Start here. SLO status, service map and RED metrics for every service. Orange lines mark injected chaos.",
              tags=["overview"])
    b.row("SLO status (storefront)")
    b.add(stat("Availability (30d)", [prom('100 * (1 - slo:sli_error:ratio_rate30d{sloth_id="storefront-availability"})', instant=True)], "percent",
               steps((None, RED), (99.5, GREEN)), "Share of /api requests that did not fail with 5xx. Objective 99.5%.", decimals=3), 4, 4)
    b.add(stat("Latency SLI (30d)", [prom('100 * (1 - slo:sli_error:ratio_rate30d{sloth_id="storefront-latency"})', instant=True)], "percent",
               steps((None, RED), (99, GREEN)), "Share of /api requests faster than 300 ms. Objective 99%.", decimals=3), 4, 4)
    b.add(stat("Error budget left", [prom('100 * clamp_min(min(slo:period_error_budget_remaining:ratio{sloth_service="storefront"}), 0)', instant=True)], "percent",
               steps((None, RED), (25, ORANGE), (50, GREEN)), "Worst of the two SLOs. 100% means nothing spent in the 30 day window; shown as 0% once overspent. On a fresh stack the 30 day window holds only minutes of data, so early readings swing fast: treat them as warming up.", decimals=1), 4, 4)
    b.add(stat("Burn rate (5m)", [prom('max(slo:current_burn_rate:ratio{sloth_service="storefront"})', instant=True)], "none",
               steps((None, GREEN), (1, YELLOW), (6, ORANGE), (14.4, RED)),
               "1x spends the budget exactly over 30 days. 14.4x on the 1h and 5m windows pages.", decimals=1), 4, 4)
    b.add(stat("Pages firing", [prom('count(ALERTS{alertname=~"Storefront.*Burn",severity="page",alertstate="firing"}) or vector(0)', instant=True)], "none",
               steps((None, GREEN), (1, RED)), "SLO burn alerts at page severity.", mappings=alert_state_mappings()), 4, 4)
    b.add(stat("Request rate", [prom(f'sum(rate({CALLS}{{service_name="storefront",{SERVER}}}[1m]))', instant=True)], "reqps",
               steps((None, BLUE)), "Storefront server spans per second.", decimals=1, color_mode="value", graph="area"), 4, 4)

    b.row("How a request flows")
    b.add({"type": "nodeGraph", "title": "Service map", "description": "Built from the collector's servicegraph metrics. Edge size is request rate.",
           "datasource": TEMPO, "targets": [{"refId": "A", "datasource": TEMPO, "queryType": "serviceMap"}], "options": {}}, 12, 9)
    b.add(ts("Error budget remaining", [prom('100 * clamp_min(slo:period_error_budget_remaining:ratio{sloth_service="storefront"}, 0)', "{{sloth_slo}}")], "percent",
             "Falls when requests are slow or failing.", thresholds=steps((None, RED), (25, ORANGE), (50, GREEN)), vmin=0, vmax=100), 12, 9)

    b.row("RED per service (spanmetrics, computed before sampling)")
    b.add(ts("Request rate", [prom(rate_by("service_name"), "{{service_name}}")], "reqps", "Server spans per second.", stack=True), 8, 8)
    b.add(ts("Error ratio", [prom(err_ratio("service_name"), "{{service_name}}")], "percentunit", "Server spans with status ERROR.",
             thresholds=steps((None, GREEN), (0.005, RED)), vmin=0, soft_max=0.02), 8, 8)
    b.add(ts("Latency p95 (exemplars on)", [prom(quantile(0.95, "service_name"), "{{service_name}}", exemplar=True)], "ms",
             "Click a dot to open the trace in Tempo.", thresholds=steps((None, GREEN), (300, RED)), vmin=0), 8, 8)

    b.row("What is alerting and what is failing")
    b.add(table("Firing alerts", [dict(prom('ALERTS{alertstate="firing"}', instant=True), format="table")],
                "Everything Prometheus considers firing. Watchdog is always present.",
                transformations=[{"id": "organize", "options": {"excludeByName": {"Time": True, "Value": True, "__name__": True, "alertstate": True},
                                                                 "indexByName": {"alertname": 0, "severity": 1, "sloth_slo": 2}}}]), 10, 8)
    b.add(logs("Recent errors", '{service_name=~".+"} | level="error"', "Error logs from all services. Expand a line and use the trace_id link."), 14, 8)
    return b


# --------------------------------------------------------------------------- slo detail
def slo_detail():
    slo = "$slo"
    sid = 'sloth_id="storefront-$slo"'
    b = Board("e2t-slo", "SLO detail",
              "Error budget, multi-window burn rates and alert state for one SLO. Pick the SLO at the top.",
              tags=["slo"], variables=[var_custom("slo", "SLO", ["availability", "latency"], "latency")], frm="now-1h")
    b.row("Status")
    b.add(stat("SLI (30d)", [prom(f'100 * (1 - slo:sli_error:ratio_rate30d{{{sid}}})', instant=True)], "percent",
               steps((None, RED), (99, GREEN)), "Compare with the objective on the right.", decimals=3), 5, 4)
    b.add(stat("Objective", [prom(f'100 * slo:objective:ratio{{{sid}}}', instant=True)], "percent", steps((None, BLUE)),
               "availability 99.5%, latency 99%.", decimals=1, color_mode="value"), 3, 4)
    b.add(gauge("Error budget left", [prom(f'100 * clamp_min(slo:period_error_budget_remaining:ratio{{{sid}}}, 0)', instant=True)], "percent",
                steps((None, RED), (25, ORANGE), (50, GREEN))), 5, 4)
    b.add(stat("Burn rate (5m)", [prom(f'slo:current_burn_rate:ratio{{{sid}}}', instant=True)], "none",
               steps((None, GREEN), (1, YELLOW), (6, ORANGE), (14.4, RED)), decimals=1), 5, 4)
    b.add(stat("Alert state", [prom(f'count(ALERTS{{sloth_id="storefront-$slo",severity="page",alertstate="firing"}}) or vector(0)', instant=True)], "none",
               steps((None, GREEN), (1, RED)), "PAGING while a page alert for this SLO fires.", mappings=alert_state_mappings()), 6, 4)

    b.row("Budget")
    b.add(ts("Error budget burn-down", [prom(f'100 * clamp_min(slo:period_error_budget_remaining:ratio{{{sid}}}, 0)', "budget left")], "percent",
             "Percent of the 30 day budget still unspent.", thresholds=steps((None, RED), (25, ORANGE), (50, GREEN)), vmin=0, vmax=100), 12, 8)
    b.add(ts("Bad events ratio", [prom(f'slo:sli_error:ratio_rate5m{{{sid}}}', "5m"), prom(f'slo:sli_error:ratio_rate1h{{{sid}}}', "1h", ref="B"),
                                  prom(f'slo:sli_error:ratio_rate6h{{{sid}}}', "6h", ref="C")],
             "percentunit", "Share of requests that were bad (5xx for availability, over 300 ms for latency).", vmin=0), 12, 8)

    b.row("Burn rate against the alert thresholds")
    burn = lambda w, r: prom(f'slo:sli_error:ratio_rate{w}{{{sid}}} / (1 - slo:objective:ratio{{{sid}}})', w, ref=r)
    thr = lambda v, r, name: prom(f"vector({v})", name, ref=r)
    dashed = lambda name: {"matcher": {"id": "byName", "options": name},
                           "properties": [{"id": "custom.lineStyle", "value": {"fill": "dash", "dash": [8, 8]}},
                                          {"id": "custom.fillOpacity", "value": 0}, {"id": "color", "value": {"mode": "fixed", "fixedColor": RED}}]}
    b.add(ts("Page, fast pair (1h and 5m, fires above 14.4x)", [burn("1h", "A"), burn("5m", "B"), thr(14.4, "C", "threshold 14.4x")], "none",
             "Both windows must exceed the threshold. Catches a sudden outage in minutes.", vmin=0, overrides=[dashed("threshold 14.4x")]), 12, 8)
    b.add(ts("Page, slow pair (6h and 30m, fires above 6x)", [burn("6h", "A"), burn("30m", "B"), thr(6, "C", "threshold 6x")], "none",
             "Keeps the page alive until the 30m window falls under 6x, which is why resolving is slower than detecting.", vmin=0,
             overrides=[dashed("threshold 6x")]), 12, 8)
    b.add(ts("Ticket, fast pair (1d and 2h, fires above 3x)", [burn("1d", "A"), burn("2h", "B"), thr(3, "C", "threshold 3x")], "none", vmin=0,
             overrides=[dashed("threshold 3x")]), 12, 7)
    b.add(ts("Ticket, slow pair (3d and 6h, fires above 1x)", [burn("3d", "A"), burn("6h", "B"), thr(1, "C", "threshold 1x")], "none", vmin=0,
             overrides=[dashed("threshold 1x")]), 12, 7)

    b.row("Alerts")
    b.add({"type": "state-timeline", "title": "Alert state", "datasource": PROM,
           "targets": [prom(f'ALERTS{{sloth_id="storefront-$slo",alertstate="firing"}}', "{{alertname}} {{severity}}")],
           "fieldConfig": {"defaults": {"mappings": [{"type": "value", "options": {"1": {"text": "firing", "color": RED}}}],
                                        "color": {"mode": "thresholds"}, "thresholds": steps((None, GREEN), (1, RED))}, "overrides": []},
           "options": {"showValue": "never", "mergeValues": True, "legend": {"showLegend": False}}}, 24, 5)
    b.add(text("How to read this", "Page alerts need **both** windows of a pair above the threshold. "
                                   "The short window makes the alert stop soon after the problem is fixed; the long window stops it from flapping. "
                                   "Runbooks: [availability](https://github.com/mqa8668/edge-to-trace/blob/main/docs/runbooks/storefront-availability-burn.md), "
                                   "[latency](https://github.com/mqa8668/edge-to-trace/blob/main/docs/runbooks/storefront-latency-burn.md)."), 24, 3)
    return b


# --------------------------------------------------------------------------- service drill-down
def service():
    sv = 'service_name="$service"'
    b = Board("e2t-service", "Service drill-down",
              "One service: RED by route, logs and traces. Pick the service at the top.",
              tags=["service"], variables=[var_query("service", "Service", f'label_values({CALLS}{{{SERVER}}}, service_name)', current="storefront")])
    b.row("RED")
    b.add(stat("Requests per second", [prom(f'sum(rate({CALLS}{{{SERVER},{sv}}}[1m]))', instant=True)], "reqps", steps((None, BLUE)),
               decimals=1, color_mode="value", graph="area"), 4, 4)
    b.add(stat("Error ratio", [prom(f'(sum(rate({CALLS}{{{SERVER},{sv},status_code="STATUS_CODE_ERROR"}}[1m])) or vector(0)) / sum(rate({CALLS}{{{SERVER},{sv}}}[1m]))', instant=True)],
               "percentunit", steps((None, GREEN), (0.005, ORANGE), (0.05, RED)), decimals=2), 4, 4)
    b.add(stat("p95 latency", [prom(quantile(0.95, "", sv), instant=True)], "ms", steps((None, GREEN), (300, ORANGE), (800, RED)), decimals=0), 4, 4)
    b.add(stat("p99 latency", [prom(quantile(0.99, "", sv), instant=True)], "ms", steps((None, GREEN), (300, ORANGE), (800, RED)), decimals=0), 4, 4)
    b.add(table("Routes", [dict(prom(f'sum by (http_route) (rate({CALLS}{{{SERVER},{sv}}}[5m]))', instant=True), format="table", refId="A")],
                "Server spans per second by route over 5 minutes.",
                transformations=[{"id": "organize", "options": {"excludeByName": {"Time": True}, "renameByName": {"Value": "req/s", "http_route": "route"}}}]), 8, 4)
    b.add(ts("Request rate by route", [prom(rate_by("http_route", sv), "{{http_route}}")], "reqps", stack=True), 8, 8)
    b.add(ts("Error ratio by route", [prom(err_ratio("http_route", sv), "{{http_route}}")], "percentunit",
             thresholds=steps((None, GREEN), (0.005, RED)), vmin=0, soft_max=0.02), 8, 8)
    b.add(ts("Latency (exemplars on)", [prom(quantile(0.50, "", sv), "p50", "A"), prom(quantile(0.95, "", sv), "p95", "B", exemplar=True),
                                        prom(quantile(0.99, "", sv), "p99", "C")], "ms",
             "Click an exemplar dot to open the trace.", thresholds=steps((None, GREEN), (300, RED)), vmin=0), 8, 8)
    b.row("Logs and traces")
    b.add(logs("Logs", '{service_name="$service"} | json | line_format "{{.level}} {{.msg}}"',
               "Click a line, then the trace_id link, to open the trace."), 12, 11)
    b.add({"type": "table", "title": "Recent traces", "datasource": TEMPO,
           "description": "TraceQL search. Click a trace ID to open it.",
           "targets": [{"refId": "A", "datasource": TEMPO, "queryType": "traceql", "query": '{ resource.service.name = "$service" }',
                        "limit": 20, "tableType": "traces"}],
           "fieldConfig": {"defaults": {}, "overrides": []}, "options": {"showHeader": True}}, 12, 11)
    b.add(ts("Log volume by level", [dict(refId="A", datasource=LOKI, expr='sum by (level) (count_over_time({service_name="$service"}[1m]))', legendFormat="{{level}}", queryType="range")],
             "short", ds=LOKI, stack=True), 24, 6)
    return b


# --------------------------------------------------------------------------- beyla
def beyla():
    cat = 'service_name="catalog"'
    b = Board("e2t-beyla", "Beyla / eBPF",
              "The catalog service has no OpenTelemetry SDK. Beyla watches it from the kernel and produces these spans.",
              tags=["beyla", "ebpf"])
    b.add(text("What you are looking at",
               "`catalog` is a Go service with **no tracing code**. Beyla attaches eBPF probes to the process, "
               "reads the incoming `traceparent` header and emits HTTP server spans plus Postgres client spans. "
               "Everything on this page comes from those spans or from Beyla's own metrics."), 24, 3)
    b.row("Is it working")
    b.add(stat("Instrumented processes", [prom('sum(beyla_instrumented_processes) or vector(0)', instant=True)], "none",
               steps((None, RED), (1, GREEN)), "Zero means Beyla attached to nothing: see docs/troubleshooting.md.",
               mappings=[{"type": "value", "options": {"0": {"text": "NONE", "color": RED}}}]), 5, 4)
    b.add(stat("Beyla scrape", [prom('up{job="beyla"}', instant=True)], "none", steps((None, RED), (1, GREEN)),
               mappings=[{"type": "value", "options": {"0": {"text": "DOWN", "color": RED}, "1": {"text": "UP", "color": GREEN}}}]), 4, 4)
    b.add(stat("catalog requests", [prom(f'sum(rate({CALLS}{{{SERVER},{cat}}}[1m]))', instant=True)], "reqps", steps((None, BLUE)),
               decimals=1, color_mode="value", graph="area"), 5, 4)
    b.add(stat("catalog p95", [prom(quantile(0.95, "", cat), instant=True)], "ms", steps((None, GREEN), (50, ORANGE), (300, RED)), decimals=1), 5, 4)
    b.add(stat("DB query p95", [prom(f'histogram_quantile(0.95, sum by (le) (rate({BUCKET}{{span_kind="SPAN_KIND_CLIENT",{cat}}}[1m])))', instant=True)],
               "ms", steps((None, GREEN), (20, ORANGE), (100, RED)), decimals=1), 5, 4)
    b.row("What Beyla sees")
    b.add(ts("catalog HTTP requests by route", [prom(rate_by("http_route", cat), "{{http_route}}")], "reqps", stack=True), 12, 8)
    b.add(ts("catalog latency (exemplars on)", [prom(quantile(0.50, "", cat), "p50", "A"), prom(quantile(0.95, "", cat), "p95", "B", exemplar=True),
                                                 prom(quantile(0.99, "", cat), "p99", "C")], "ms", vmin=0), 12, 8)
    b.add(ts("Postgres client spans per second", [prom(f'sum by (span_name) (rate({CALLS}{{span_kind="SPAN_KIND_CLIENT",{cat}}}[1m]))', "{{span_name}}")],
             "ops", "Database calls seen from the kernel, no driver instrumentation.", stack=True), 12, 8)
    b.add(ts("Postgres query latency p95", [prom(f'histogram_quantile(0.95, sum by (le, span_name) (rate({BUCKET}{{span_kind="SPAN_KIND_CLIENT",{cat}}}[1m])))', "{{span_name}}")],
             "ms", vmin=0), 12, 8)
    b.row("Traces and logs")
    b.add({"type": "table", "title": "Recent catalog traces", "datasource": TEMPO,
           "targets": [{"refId": "A", "datasource": TEMPO, "queryType": "traceql", "query": '{ resource.service.name = "catalog" }', "limit": 20, "tableType": "traces"}],
           "fieldConfig": {"defaults": {}, "overrides": []}, "options": {"showHeader": True}}, 12, 9)
    b.add(logs("catalog logs", '{service_name="catalog"}'), 12, 9)
    b.add(ts("Beyla internal: exported spans", [prom('rate(beyla_otel_trace_exports_total[1m])', "exports/s")], "ops",
             "Beyla's own counter of trace batches sent to the collector."), 24, 6)
    return b


def main():
    os.makedirs(OUT, exist_ok=True)
    for board in (overview(), slo_detail(), service(), beyla()):
        path = os.path.join(OUT, board.uid + ".json")
        with open(path, "w") as f:
            json.dump(board.json(), f, indent=2, sort_keys=True)
            f.write("\n")
        print("wrote", os.path.relpath(path))


if __name__ == "__main__":
    main()
