// Every pattern as the mixer draws it in the browser, for comparison with
// the same pages drawn without the browser (tools/pattern_audit.lua).
//
//   node site/tools/pattern-audit.mjs OUTDIR [backdrop=dark] [patterns=a,b]
//
// Serves the site with vite (site/public/bake must hold the baked pages,
// as `just site-bake` or tools/pattern-audit.sh leaves them), opens the
// mixer on ?pattern=NAME for every pattern the catalog lists, waits for the
// page to grow and writes, per pattern, OUTDIR/<name>.canvas.png (the
// mixer's canvas alone, as its renderer drew it) and OUTDIR/<name>.sheet.png
// (the sheet as the visitor sees it, the text laid over). OUTDIR/mixer.tsv
// lists each pattern, the renderer, the canvas size, the setup line the
// mixer offers and any page error. Needs Google Chrome.
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright-core";

const SITE = join(dirname(fileURLToPath(import.meta.url)), "..");
const out = process.argv[2];
if (!out) throw new Error("usage: node site/tools/pattern-audit.mjs OUTDIR [backdrop=dark] [patterns=a,b]");
const opts = Object.fromEntries(process.argv.slice(3).map((a) => a.split("=")));
mkdirSync(out, { recursive: true });
const PORT = process.env.PATTERN_AUDIT_PORT || "5179";
const URL = `http://127.0.0.1:${PORT}/mixer/`;

const catalog = JSON.parse(readFileSync(join(SITE, "public/bake/catalog.json"), "utf8"));
const names = opts.patterns ? opts.patterns.split(",") : catalog.patterns.map((p) => p.name);

const server = spawn("npx", ["vite", "--port", PORT, "--strictPort", "--host", "127.0.0.1"], { cwd: SITE, stdio: ["ignore", "ignore", "pipe"] });
let browser;
const rows = ["pattern\trenderer\tcanvas\tsetup\terror"];
try {
  for (let i = 0; i < 200; i++) {
    try { if ((await fetch(URL)).ok) break; } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 150));
  }
  browser = await chromium.launch({ channel: "chrome", headless: true, args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] });
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1 });
  for (const name of names) {
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    const q = new URLSearchParams({ pattern: name });
    if (opts.backdrop) q.set("backdrop", opts.backdrop);
    await page.goto(`${URL}?${q}`);
    let status = "";
    try {
      await page.locator(".status", { hasText: /Grown in|went wrong|could not/ }).waitFor({ timeout: 180000 });
      status = await page.locator(".status").textContent();
    } catch (e) { errors.push(`timeout: ${e.message.split("\n")[0]}`); }
    if (/went wrong|could not/.test(status)) errors.push(status);
    const canvas = await page.evaluate(() => {
      const c = document.querySelector(".sheet canvas");
      return c ? { url: c.toDataURL("image/png"), w: c.width, h: c.height } : null;
    });
    if (canvas) writeFileSync(join(out, `${name}.canvas.png`), Buffer.from(canvas.url.split(",")[1], "base64"));
    await page.locator(".sheet").screenshot({ path: join(out, `${name}.sheet.png`) });
    const setup = await page.locator(".controls pre code").first().textContent().catch(() => "");
    const renderer = (status.match(/\(([^)]*)\)/) || [])[1] || "";
    rows.push([name, renderer, canvas ? `${canvas.w}x${canvas.h}` : "", setup.replace(/\s+/g, " "), errors.join(" | ")].join("\t"));
    console.log(`${name}: ${renderer} ${canvas ? `${canvas.w}x${canvas.h}` : "no canvas"} ${errors.join(" | ")}`);
    await page.close();
  }
} finally {
  writeFileSync(join(out, "mixer.tsv"), rows.join("\n") + "\n");
  await browser?.close();
  server.kill();
}
