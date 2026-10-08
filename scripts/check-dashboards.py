#!/usr/bin/env python3
"""Run every panel query of every provisioned dashboard through Grafana's /api/ds/query and report empty panels.

usage: check-dashboards.py [--url http://localhost:3000] [--from now-30m] [--allow-empty TITLE ...]
Reads GRAFANA_ADMIN_PASSWORD from the environment or .env. Exit code 1 if a panel errors or returns no data.
"""
import argparse
import base64
import json
import os
import sys
import urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("--url", default="http://localhost:3000")
ap.add_argument("--from", dest="frm", default="now-30m")
ap.add_argument("--allow-empty", nargs="*", default=[])
args = ap.parse_args()

pw = os.environ.get("GRAFANA_ADMIN_PASSWORD")
if not pw and os.path.exists(".env"):
    for line in open(".env"):
        if line.startswith("GRAFANA_ADMIN_PASSWORD="):
            pw = line.strip().split("=", 1)[1]
auth = "Basic " + base64.b64encode(f"admin:{pw}".encode()).decode()


def call(path, body=None):
    req = urllib.request.Request(args.url + path, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": auth, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def subst(obj, vars_):
    s = json.dumps(obj)
    for k, v in vars_.items():
        s = s.replace("${" + k + "}", v).replace("$" + k, v)
    return json.loads(s)


bad = 0
total = 0
for hit in call("/api/search?type=dash-db&tag=edge-to-trace"):
    d = call("/api/dashboards/uid/" + hit["uid"])["dashboard"]
    vars_ = {}
    for v in d.get("templating", {}).get("list", []):
        vars_[v["name"]] = (v.get("current") or {}).get("value") or "storefront"
    print(f"== {d['title']} ({d['uid']})")
    for p in d["panels"]:
        if p["type"] in ("row", "text"):
            continue
        total += 1
        queries = []
        targets = p.get("targets", [])
        if p["type"] == "nodeGraph":
            # The Tempo service map query runs in the browser, so check the Prometheus series it is built from.
            targets = [{"refId": "A", "datasource": {"type": "prometheus", "uid": "prometheus"},
                        "expr": "sum by (client, server) (rate(traces_service_graph_request_total[5m]))", "instant": True}]
        for t in targets:
            t = subst(t, vars_)
            if t.get("hide"):
                continue
            t.setdefault("datasource", p.get("datasource"))
            t.update({"intervalMs": 15000, "maxDataPoints": 500})
            queries.append(t)
        status, detail = "ok", ""
        try:
            res = call("/api/ds/query", {"queries": queries, "from": args.frm, "to": "now"})["results"]
            rows = 0
            for ref, r in res.items():
                if r.get("error"):
                    status, detail = "ERROR", r["error"][:120]
                for fr in r.get("frames", []):
                    vals = fr.get("data", {}).get("values", [])
                    rows += max((len(c) for c in vals), default=0)
            if status == "ok" and rows == 0:
                status = "allowed-empty" if p["title"] in args.allow_empty else "EMPTY"
        except Exception as e:  # noqa: BLE001
            status, detail = "ERROR", str(e)[:120]
        if status in ("ERROR", "EMPTY"):
            bad += 1
        print(f"  {status:13} {p['title']} {detail}")
print(f"{total} panels checked, {bad} problems")
sys.exit(1 if bad else 0)
