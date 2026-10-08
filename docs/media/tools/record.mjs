// Records the edge-to-trace story with Playwright. Run from a scratch directory, not from the repo.
// Needs: ssh tunnels to Grafana (:13000) and alert-sink (:19095), and a way to run chaos (CHAOS_CMD, a shell command).
import {chromium} from 'playwright';
import {spawn} from 'node:child_process';
import fs from 'node:fs';

const G = process.env.GRAFANA || 'http://localhost:13000';
const SINK = process.env.SINK || 'http://localhost:19095';
const CHAOS = process.env.CHAOS_CMD;
const out = process.env.OUT || './rec';
fs.mkdirSync(out, {recursive: true});

const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: {width: 1600, height: 900},
  colorScheme: 'dark',
  recordVideo: {dir: out, size: {width: 1600, height: 900}},
});
const page = await ctx.newPage();
const t0 = Date.now();
const marks = {};
const mark = (n) => { marks[n] = (Date.now() - t0) / 1000; console.log('mark', n, marks[n].toFixed(1)); };
const wait = (ms) => page.waitForTimeout(ms);

const pageStatus = async () => {
  try {
    const r = await fetch(`${SINK}/alerts?alertname=StorefrontLatencyBurn`);
    const a = (await r.json()).filter((x) => x.labels.severity === 'page');
    return a.length ? a[0].status : 'none';
  } catch { return 'err'; }
};

// 1. baseline overview
await page.goto(`${G}/d/e2t-overview?kiosk&from=now-15m&to=now&refresh=5s`);
await page.waitForSelector('text=Platform overview', {timeout: 30000}).catch(() => {});
await wait(9000);
mark('baseline_end');

// 2. inject chaos, watch the overview react
mark('chaos_injected');
// CHAOS_CMD injects the fault and blocks until the page fires (scripts/demo.sh run does exactly that).
// Async on purpose: a blocking call would stall the event loop and Playwright would stop receiving video frames.
const chaos = spawn('sh', ['-c', CHAOS], {stdio: 'inherit'});
let chaosDone = false;
chaos.on('exit', () => { chaosDone = true; });
const tWait = Date.now();
while (!chaosDone && Date.now() - tWait < 480000) await wait(1000);
const fired = (await pageStatus()) === 'firing';
mark('alert_fired');
await wait(8000);
mark('overview_after_end');

// 3. SLO detail
await page.goto(`${G}/d/e2t-slo?kiosk&var-slo=latency&from=now-15m&to=now&refresh=5s`);
await wait(12000);
mark('slo_end');

// 4. service drill-down and the exemplar
await page.goto(`${G}/d/e2t-service?kiosk&var-service=storefront&from=now-15m&to=now`);
await wait(6000);
mark('service_loaded');
const panel = page.locator('[data-testid="data-testid Panel header Latency (exemplars on)"]');
const box = await panel.boundingBox();
if (!box) throw new Error('latency panel not found');
await page.screenshot({path: `${out}/service.png`});
const plot = {x: box.x + 60, y: box.y + 40, w: box.width - 90, h: box.height - 120};
let hit = false;
// scan right to left (chaos is the recent part) at the top of the plot where the slow exemplars sit
outer: for (let yy = 0; yy < plot.h; yy += 5) {
  for (let xx = plot.w; xx > 0; xx -= 6) {
    await page.mouse.move(plot.x + xx, plot.y + yy);
    if (await page.getByText('Query with Tempo').first().isVisible().catch(() => false)) { hit = true; break outer; }
  }
}
if (!hit) throw new Error('exemplar not found by hover scan');
mark('exemplar_hover');
await wait(2500);
await page.getByText('Query with Tempo').first().click();
mark('exemplar_clicked');
await page.waitForSelector('text=recs.rank_candidates', {timeout: 30000});
await wait(4000);
// 5. select the injected span
await page.getByText('recs.rank_candidates').first().click();
await wait(4000);
mark('trace_end');
await page.screenshot({path: `${out}/trace.png`});
// 6. logs for this span
const logsBtn = page.getByRole('button', {name: /Logs for this span/i}).first();
if (await logsBtn.isVisible().catch(() => false)) {
  await logsBtn.click();
  await wait(7000);
  await page.screenshot({path: `${out}/logs.png`});
}
mark('logs_end');

const video = page.video();
await ctx.close();
await browser.close();
fs.writeFileSync(`${out}/marks.json`, JSON.stringify({marks, fired, video: await video.path()}, null, 2));
console.log('done', await video.path());
