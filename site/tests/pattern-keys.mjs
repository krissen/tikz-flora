// Every pattern key of the catalog (Settings.PATTERN, as catalog.pattern_keys)
// reaches all four places a mixer carries it: the control, the \florasetup
// line, the worker's spec and the URL's starting value. The keys come from
// the catalog, so a new pattern key that one of them leaves out fails here.
//
//   texlua tools/catalog.lua > build/catalog.json
//   node site/tests/pattern-keys.mjs build/catalog.json
import { readFileSync } from "node:fs";
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

const mixer = readFileSync(join(SITE, "src/lib/Mixer.svelte"), "utf8");
const worker = readFileSync(join(SITE, "src/lib/render.worker.js"), "utf8");
// The control and the worker go through the catalog's list, not through names.
check(/\{#each pat\.keys as k\}/.test(mixer), "the mixer's pattern controls are not made from the catalog's keys");
check(/pairs\(Settings\.PATTERN\)/.test(worker) && /Settings\.SPEC\[k\]/.test(worker), "the worker does not copy every Settings.PATTERN key to the spec");
check(/patternFromQuery\(query, m\)/.test(mixer), "the mixer does not start from the URL's pattern keys");

for (const k of pat.keys) {
  const d = pat.defaults[k];
  check(d !== undefined, `${k}: no default`);
  check(pat.choices[k] || pat.range[k], `${k}: the catalog gives neither values nor a range`);
  // Control: a choice key lists values (its default among them), a range key a range.
  if (pat.choices[k]) check(pat.choices[k].includes(String(d)), `${k}: default ${d} is not among ${pat.choices[k]}`);
  // Setup line: a value that differs is written, the default is not.
  const others = pat.choices[k] ? pat.choices[k].filter((v) => v !== String(d)) : [pat.range[k][0] === d ? pat.range[k][1] : pat.range[k][0]];
  for (const v of others) {
    const line = patternParts({ name: "asanoha", [k]: v }, meta);
    check(line.includes(`${k}=${v}`), `${k}=${v} is not in the setup line: ${line}`);
    // URL: ?key=value opens on it.
    const st = patternFromQuery(new URLSearchParams(`pattern=asanoha&${k}=${v}`), meta);
    check(String(st[k]) === String(v), `?${k}=${v} is not kept: ${JSON.stringify(st)}`);
  }
  check(!patternParts({ name: "asanoha", [k]: d }, meta).some((p) => p.startsWith(k + "=")), `${k}: the default is written to the line`);
  check(patternFromQuery(new URLSearchParams(`${k}=nonesuch`), meta)[k] === d, `?${k}=nonesuch is not ignored`);
}
check(patternParts({ name: "", hero: "rose" }, meta).length === 0, "flora has pattern keys");

if (failures) { console.error(`${failures} failure(s)`); process.exit(1); }
console.log(`pattern-keys: ok (${pat.keys.join(", ")})`);
