// Every pattern key of the catalog (Settings.PATTERN, as catalog.pattern_keys)
// reaches all four places a mixer carries it: the control, the \florasetup
// line, the worker's spec and the URL's starting value. The keys come from
// the catalog, so a new pattern key that one of them leaves out fails here.
//
//   texlua tools/catalog.lua > build/catalog.json
//   node site/tests/pattern-keys.mjs build/catalog.json
//
// The first part is the line and the URL's reading, as functions; the second
// drives the built site (site/dist, so `npm run build` first; just test-site
// does) in Chrome: for each key a control exists, using it writes the key to
// the line and changes the sheet (so the worker passes it on), and ?key=value
// opens on it.
import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { chromium } from "playwright-core";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { patternDefaults, patternParts, patternFromQuery } from "../src/lib/setup.js";

const SITE = join(dirname(fileURLToPath(import.meta.url)), "..");
const catalog = JSON.parse(readFileSync(process.argv[2] ?? join(SITE, "public/bake/catalog.json"), "utf8"));
const meta = { catalog };
let failures = 0;
const check = (c, m) => { if (!c) { failures++; console.error("FAIL: " + m); } };

const pat = patternDefaults(meta);
check(pat.keys.length >= 4, `the catalog lists ${pat.keys.length} pattern keys`);
check(pat.keys.includes("hero"), "hero is not among the catalog's pattern keys");

for (const k of pat.keys) {
  const d = pat.defaults[k];
  check(d !== undefined, `${k}: no default`);
  check(pat.choices[k] || pat.range[k], `${k}: the catalog gives neither values nor a range`);
  // Control: a choice key lists values (its default among them), a range key a range.
  if (pat.choices[k]) check(pat.choices[k].includes(String(d)), `${k}: default ${d} is not among ${pat.choices[k]}`);
  // Setup line: a value that differs is written, the default is not.
  const others = pat.choices[k] ? pat.choices[k].filter((v) => v !== String(d)) : [pat.range[k][0] === d ? pat.range[k][1] : pat.range[k][0]];
  for (const v of others) {
    const line = patternParts({ name: "rosette_lattice", [k]: v }, meta);
    check(line.includes(`${k}=${v}`), `${k}=${v} is not in the setup line: ${line}`);
    // URL: ?key=value opens on it.
    const st = patternFromQuery(new URLSearchParams(`pattern=rosette_lattice&${k}=${v}`), meta);
    check(String(st[k]) === String(v), `?${k}=${v} is not kept: ${JSON.stringify(st)}`);
  }
  check(!patternParts({ name: "rosette_lattice", [k]: d }, meta).some((p) => p.startsWith(k + "=")), `${k}: the default is written to the line`);
  check(patternFromQuery(new URLSearchParams(`${k}=nonesuch`), meta)[k] === d, `?${k}=nonesuch is not ignored`);
}
check(patternParts({ name: "", hero: "rose" }, meta).length === 0, "flora has pattern keys");

// The built mixer: every catalog key has a control; a non-default value
// reaches the line and changes the picture; the URL opens on it. The page
// is rosette_lattice, which has fields, a ground and straps, so that every
// key (saturation, ground and bands among them) changes what it paints.
if (!existsSync(join(SITE, "dist/mixer/index.html"))) check(false, "site/dist is not built (npm run build in site/)");
else {
  const PORT = process.env.PATTERN_KEYS_PORT || "4318";
  const base = `http://127.0.0.1:${PORT}/mixer/`;
  const server = spawn("npx", ["vite", "preview", "--port", PORT, "--strictPort", "--host", "127.0.0.1"], { cwd: SITE, stdio: "ignore" });
  await new Promise((r) => setTimeout(r, 3000));
  const browser = await chromium.launch({ channel: "chrome", headless: true, args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] });
  try {
    const sum = (page) => page.evaluate(() => {
      const c = document.querySelector(".sheet canvas");
      const d = c.getContext("2d").getImageData(0, 0, c.width, c.height).data;
      let h = 0;
      for (let i = 0; i < d.length; i += 4 * 5) h = (h * 31 + d[i] + d[i + 1] * 3 + d[i + 3]) | 0;
      return h;
    });
    const settled = async (page) => { await page.waitForTimeout(800); await page.locator(".status", { hasText: "Grown in" }).waitFor({ timeout: 120000 }); };
    const page = await browser.newPage({ viewport: { width: 1500, height: 1000 } });
    await page.goto(`${base}?layout=left&pattern=rosette_lattice`);
    await settled(page);
    const code = () => page.locator(".controls pre code").textContent();
    const before = await sum(page);
    for (const k of pat.keys) {
      const ctl = page.locator(`details.pattern [data-pattern-key="${k}"]`);
      if (await ctl.count() !== 1) { check(false, `${k}: the mixer has no control for it`); continue; }
      const v = pat.choices[k] ? pat.choices[k].find((x) => x !== String(pat.defaults[k])) : String(pat.range[k][1]);
      if (pat.choices[k]) await ctl.getByRole("button", { name: v, exact: true }).click();
      else await ctl.locator('input[type="range"]').fill(v);
      await settled(page);
      check(new RegExp(`pattern=rosette_lattice(, \\w+=[^,}]+)*, ${k}=${v}`).test(await code()), `${k}=${v} set by the control is not in the line: ${await code()}`);
      check(await sum(page) !== before, `${k}=${v} set by the control does not change the sheet (the worker drops it?)`);
      // Back to the default, for the next key to be compared with the same page.
      if (pat.choices[k]) await ctl.getByRole("button", { name: String(pat.defaults[k]), exact: true }).click();
      else await ctl.locator('input[type="range"]').fill(String(pat.defaults[k]));
      await settled(page);
      check(await sum(page) === before, `${k} back at its default does not restore the sheet`);
      const url = await browser.newPage({ viewport: { width: 1500, height: 1000 } });
      await url.goto(`${base}?layout=left&pattern=rosette_lattice&${k}=${v}`);
      await settled(url);
      check(new RegExp(`${k}=${v}`).test(await url.locator(".controls pre code").textContent()), `?${k}=${v} does not open the mixer on it`);
      await url.close();
    }
  } finally {
    await browser.close();
    server.kill();
  }
}

if (failures) { console.error(`${failures} failure(s)`); process.exit(1); }
console.log(`pattern-keys: ok (${pat.keys.join(", ")})`);
