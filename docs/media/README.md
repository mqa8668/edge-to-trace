# Media

How the README visuals were made, so they can be reproduced. Everything shown is real output from a running stack with fictional "Acme" data.

| File | What it is | How it was made |
|---|---|---|
| `edge-to-trace.mp4` | 60 second overview video | Remotion project in `video/`, using clips recorded from the running stack |
| `hero.gif` | Spike, page, exemplar, trace | `ffmpeg` palette GIF cut from the same clips |
| `make-demo.gif` | The `make demo` narrative in a terminal | `REPLAY_DIR=docs/media/tools vhs docs/media/make-demo.tape`. It replays `tools/demo-transcript.txt`, the captured output of a real `scripts/demo.sh run` (progress counters removed, repeated span rows merged, long URLs shortened) |
| `overview.png`, `slo-detail.png`, `trace-waterfall.png`, `beyla.png` | Screenshots, 1600x900, dark theme | `tools/shots.mjs` and `tools/record.mjs` (Playwright) |

## Re-recording

1. `make demo` style run on any Linux Docker host, let about 8 minutes of baseline traffic accumulate.
2. Make Grafana (3000), Prometheus (9090) and alert-sink (9095) reachable on localhost, for example with `ssh -L` if the stack runs elsewhere.
3. In a scratch directory (not in this repo): `npm i playwright && npx playwright install chromium`, then run `tools/record.mjs` with `CHAOS_CMD` set to a command that injects the fault and waits for the page (`scripts/demo.sh run` does this).
4. `tools/cut.sh` trims and time-lapses the recording into clips, `video/` turns them into the MP4 (`npm i && npm run render`).

The video project needs Node 20 or newer. Its `public/*.mp4` clips are not committed.
