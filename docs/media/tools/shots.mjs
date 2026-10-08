// Static screenshots for the README, taken while the chaos fault is active.
import {chromium} from 'playwright';
import fs from 'node:fs';
const G = process.env.GRAFANA || 'http://localhost:13000';
const out = process.env.OUT || './rec';
fs.mkdirSync(out, {recursive: true});
const browser = await chromium.launch();
const ctx = await browser.newContext({viewport: {width: 1600, height: 900}, colorScheme: 'dark', deviceScaleFactor: 1});
const page = await ctx.newPage();
const shots = [
  ['overview', `${G}/d/e2t-overview?kiosk&from=now-20m&to=now`, 12000],
  ['slo-detail', `${G}/d/e2t-slo?kiosk&var-slo=latency&from=now-20m&to=now`, 12000],
  ['beyla', `${G}/d/e2t-beyla?kiosk&from=now-20m&to=now`, 12000],
];
for (const [name, url, ms] of shots) {
  for (let k = 0; k < 4; k++) {
    await page.goto(url, {waitUntil: 'domcontentloaded', timeout: 60000}).catch(() => {});
    await page.waitForTimeout(ms);
    const broken = await page.getByText('Error loading').count();
    if (!broken) break;
    console.log('retry', name);
  }
  await page.screenshot({path: `${out}/${name}.png`});
  console.log('shot', name);
}
await browser.close();
