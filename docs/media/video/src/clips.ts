// Footage clips in public/, recorded by record.mjs. Durations in seconds of the trimmed, time-lapsed clips.
export type Clip = {file: string; seconds: number; caption: string; sub: string; tag: string};

export const clips: Clip[] = [
  {file: 'clip1-overview.mp4', seconds: 11, tag: '1', caption: '800 ms injected into recs', sub: 'The orange line is the chaos annotation. Latency and error budget react within a minute.'},
  {file: 'clip2-slo.mp4', seconds: 8, tag: '2', caption: 'Burn-rate page in about 2 minutes', sub: 'Both windows cross 14.4x, so the SLO alert fires and a message goes out.'},
  {file: 'clip3-exemplar.mp4', seconds: 8.5, tag: '3', caption: 'Exemplar to trace', sub: 'One click on a slow request in the latency graph opens its trace in Tempo.'},
  {file: 'clip4-trace.mp4', seconds: 11, tag: '4', caption: 'Root cause: recs.rank_candidates, 802 ms', sub: 'The injected delay, then the logs of the same request by trace_id.'},
];
