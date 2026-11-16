// Draws scenes (tools/band_probe.lua, or any pdfout.lua scene) with
// flora's WebGL2 and 2D canvas renderers in headless Chrome, as the mixer
// draws a page, and saves each as a PNG.
//
//   node site/tools/band-probe.mjs SCENE.json OUTDIR SCALE...
//
// The scene is copied under site/public/bake/scenes/ to be served. Writes
// OUTDIR/<name>-<mode>-<scale>.png for each scale (device pixels per bp).
// Needs Google Chrome.
import { spawn } from "node:child_process";
import { copyFileSync, mkdirSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const SITE = join(dirname(fileURLToPath(import.meta.url)), "..");
const [scene, out, ...scales] = process.argv.slice(2);
if (!scene || !out || !scales.length) throw new Error("usage: node site/tools/band-probe.mjs SCENE.json OUTDIR SCALE...");
mkdirSync(out, { recursive: true });
mkdirSync(join(SITE, "public/bake/scenes"), { recursive: true });
const name = basename(scene, ".json");
copyFileSync(scene, join(SITE, "public/bake/scenes", name + ".json"));
const PORT = process.env.BAND_PROBE_PORT || "5181";
const base = `http://127.0.0.1:${PORT}/tools/scene.html`;
const server = spawn("npx", ["vite", "--port", PORT, "--strictPort", "--host", "127.0.0.1"], { cwd: SITE, stdio: ["ignore", "ignore", "pipe"] });
let browser;
try {
  for (let i = 0; i < 200; i++) {
    try { if ((await fetch(base)).ok) break; } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 150));
  }
  browser = await chromium.launch({ channel: "chrome", headless: true, args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] });
  const page = await browser.newPage();
  for (const mode of ["webgl", "canvas2d"]) {
    for (const s of scales) {
      await page.goto(`${base}?scene=/bake/scenes/${name}.json&scale=${s}&mode=${mode}`);
      await page.waitForFunction(() => window.drawn, null, { timeout: 60000 });
      const url = await page.evaluate(() => document.getElementById("c").toDataURL("image/png"));
      const file = join(out, `${name}-${mode}-${s}.png`);
      writeFileSync(file, Buffer.from(url.split(",")[1], "base64"));
      console.log(file, await page.evaluate(() => window.drawn));
    }
  }
} finally {
  await browser?.close();
  server.kill();
}
