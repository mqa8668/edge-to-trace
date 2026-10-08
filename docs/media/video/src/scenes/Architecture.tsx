import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';
import {C, mono, sans} from '../theme';

type N = {id: string; x: number; y: number; w: number; label: string; sub: string; color: string; at: number};
const nodes: N[] = [
  {id: 'k6', x: 150, y: 250, w: 190, label: 'k6', sub: '5 req/s', color: C.dim, at: 0},
  {id: 'sf', x: 450, y: 250, w: 230, label: 'storefront', sub: 'Elixir, OTel SDK', color: C.blue, at: 8},
  {id: 'rc', x: 770, y: 250, w: 210, label: 'recs', sub: 'Python, OTel SDK', color: C.blue, at: 16},
  {id: 'ct', x: 1070, y: 250, w: 210, label: 'catalog', sub: 'Go, no SDK', color: C.blue, at: 24},
  {id: 'pg', x: 1370, y: 250, w: 190, label: 'Postgres', sub: '', color: C.dim, at: 32},
  {id: 'by', x: 1070, y: 440, w: 210, label: 'Beyla', sub: 'eBPF, kernel level', color: C.orange, at: 190},
  {id: 'oc', x: 620, y: 520, w: 260, label: 'OTel Collector', sub: 'spanmetrics, sampling', color: C.teal, at: 170},
  {id: 'al', x: 1370, y: 520, w: 190, label: 'Alloy', sub: 'container logs', color: C.teal, at: 200},
  {id: 'pr', x: 330, y: 760, w: 230, label: 'Prometheus', sub: 'RED, SLO rules', color: C.teal, at: 215},
  {id: 'tp', x: 640, y: 760, w: 190, label: 'Tempo', sub: 'traces', color: C.teal, at: 225},
  {id: 'lk', x: 1370, y: 760, w: 190, label: 'Loki', sub: 'logs', color: C.teal, at: 235},
  {id: 'gf', x: 1000, y: 940, w: 220, label: 'Grafana', sub: 'dashboards', color: C.green, at: 260},
  {id: 'am', x: 330, y: 940, w: 230, label: 'Alertmanager', sub: 'burn-rate alerts', color: C.red, at: 285},
  {id: 'tg', x: 640, y: 940, w: 190, label: 'Telegram', sub: 'the page', color: C.red, at: 300},
];
const byId = Object.fromEntries(nodes.map((n) => [n.id, n]));

type E = {a: string; b: string; kind: 'req' | 'tel'; at: number; bend?: number};
const edges: E[] = [
  {a: 'k6', b: 'sf', kind: 'req', at: 20},
  {a: 'sf', b: 'rc', kind: 'req', at: 40},
  {a: 'rc', b: 'ct', kind: 'req', at: 50},
  {a: 'ct', b: 'pg', kind: 'req', at: 60},
  {a: 'sf', b: 'ct', kind: 'req', at: 45, bend: -120},
  {a: 'sf', b: 'oc', kind: 'tel', at: 170},
  {a: 'rc', b: 'oc', kind: 'tel', at: 175},
  {a: 'by', b: 'oc', kind: 'tel', at: 195},
  {a: 'ct', b: 'al', kind: 'tel', at: 205},
  {a: 'oc', b: 'pr', kind: 'tel', at: 220},
  {a: 'oc', b: 'tp', kind: 'tel', at: 228},
  {a: 'al', b: 'lk', kind: 'tel', at: 240},
  {a: 'pr', b: 'gf', kind: 'tel', at: 265, bend: 60},
  {a: 'tp', b: 'gf', kind: 'tel', at: 268},
  {a: 'lk', b: 'gf', kind: 'tel', at: 270},
  {a: 'pr', b: 'am', kind: 'tel', at: 290},
  {a: 'am', b: 'tg', kind: 'tel', at: 305},
];

const pt = (e: E, t: number) => {
  const a = byId[e.a];
  const b = byId[e.b];
  const mx = (a.x + b.x) / 2;
  const my = (a.y + b.y) / 2;
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const len = Math.hypot(dx, dy) || 1;
  const bend = e.bend ?? 0;
  const cx = mx + (-dy / len) * bend;
  const cy = my + (dx / len) * bend;
  const u = 1 - t;
  return {x: u * u * a.x + 2 * u * t * cx + t * t * b.x, y: u * u * a.y + 2 * u * t * cy + t * t * b.y, cx, cy};
};

const pathOf = (e: E) => {
  const a = byId[e.a];
  const b = byId[e.b];
  const {cx, cy} = pt(e, 0.5);
  // control point of the quadratic curve that passes through pt(0.5)
  const qx = 2 * cx - (a.x + b.x) / 2;
  const qy = 2 * cy - (a.y + b.y) / 2;
  return `M ${a.x} ${a.y} Q ${qx} ${qy} ${b.x} ${b.y}`;
};

export const Architecture: React.FC = () => {
  const f = useCurrentFrame();
  const caption =
    f < 165
      ? ['A request crosses three languages', 'storefront (Elixir) calls recs (Python) and catalog (Go), which queries Postgres.']
      : f < 280
        ? ['Telemetry leaves every service', 'SDK spans, eBPF spans and logs meet in the collector, then Prometheus, Tempo and Loki.']
        : ['SLO burn rates page a human', 'Prometheus rules feed Alertmanager. Grafana ties metrics, traces and logs together.'];
  const fadeIn = interpolate(f, [0, 12], [0, 1], {extrapolateRight: 'clamp'});
  return (
    <AbsoluteFill style={{background: C.bg, opacity: fadeIn}}>
      <div style={{position: 'absolute', left: 90, top: 56}}>
        <div style={{fontFamily: sans, fontSize: 54, fontWeight: 800, color: C.text}}>{caption[0]}</div>
        <div style={{fontFamily: sans, fontSize: 28, color: C.dim, marginTop: 8}}>{caption[1]}</div>
      </div>
      <svg width={1920} height={1080} style={{position: 'absolute', inset: 0}}>
        <g transform="translate(250, 20)">
        {edges.map((e, i) => {
          const p = interpolate(f, [e.at, e.at + 14], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
          if (p <= 0) return null;
          const col = e.kind === 'req' ? C.blue : C.teal;
          // packets
          const period = e.kind === 'req' ? 38 : 52;
          const packets = [0, 1].map((k) => {
            const t = (((f - e.at) / period + k / 2) % 1 + 1) % 1;
            const q = pt(e, t);
            return <circle key={k} cx={q.x} cy={q.y} r={e.kind === 'req' ? 8 : 6} fill={col} opacity={p} />;
          });
          return (
            <g key={i} opacity={p}>
              <path d={pathOf(e)} stroke={col} strokeOpacity={0.35} strokeWidth={3} fill="none" strokeDasharray={e.kind === 'tel' ? '10 8' : undefined} />
              {packets}
            </g>
          );
        })}
        {nodes.map((n) => {
          const p = interpolate(f, [n.at, n.at + 12], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
          if (p <= 0) return null;
          const h = 88;
          return (
            <g key={n.id} opacity={p} transform={`translate(${n.x - n.w / 2}, ${n.y - h / 2 + (1 - p) * 14})`}>
              <rect width={n.w} height={h} rx={16} fill={C.panel} stroke={n.color} strokeWidth={2.5} />
              <text x={n.w / 2} y={n.sub ? 40 : 54} textAnchor="middle" fontFamily={sans} fontWeight={600} fontSize={28} fill={C.text}>{n.label}</text>
              {n.sub ? <text x={n.w / 2} y={68} textAnchor="middle" fontFamily={mono} fontSize={17} fill={C.dim}>{n.sub}</text> : null}
            </g>
          );
        })}
        </g>
      </svg>
    </AbsoluteFill>
  );
};
