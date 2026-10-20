import assert from "node:assert/strict";
import { test } from "node:test";
import { parseReport, summarize, parseOptions, renderHtml } from "../../script/performance/results.mjs";

const fixture = () => ({
  lighthouseVersion: "13.5.0", environment: { hostUserAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/155.0.0.0 Safari/537.36" },
  requestedUrl: "https://private.invalid/private?token=SECRET", runWarnings: ["SECRET"],
  audits: {
    metrics: { details: { items: [{ observedLargestContentfulPaint: 2500, largestContentfulPaint: 999,
      observedFirstContentfulPaint: 1800, firstContentfulPaint: 999, timeToFirstByte: 800,
      observedCumulativeLayoutShift: 0.1, cumulativeLayoutShift: 999, totalBlockingTime: 120 }] } },
    "resource-summary": { details: { items: [{ resourceType: "total", transferSize: 12345, requestCount: 12 }] } }
  }
});

test("uses observed trace metrics and keeps only safe selected fields", () => {
  const row = parseReport(fixture());
  assert.deepEqual(row.metrics, { lcp: 2500, fcp: 1800, ttfb: 800, cls: 0.1, tbt: 120 });
  assert.deepEqual(row.resources, { transferBytes: 12345, requests: 12 });
  assert.equal(row.browser, "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/155.0.0.0 Safari/537.36");
  assert.equal(JSON.stringify(row).includes("SECRET"), false);
});

test("missing, nonfinite, negative metrics and Lighthouse runtime errors fail as infrastructure", () => {
  for (const bad of [null, NaN, -1]) {
    const report = fixture(); report.audits.metrics.details.items[0].observedLargestContentfulPaint = bad;
    assert.equal(parseReport(report).failure, "invalid-metrics");
  }
  const report = fixture(); report.runtimeError = { code: "ERRORED_DOCUMENT_REQUEST", message: "SECRET" };
  assert.deepEqual(parseReport(report), { failure: "navigation" });
});

test("median gates are inclusive and diagnostics do not become gates or field INP", () => {
  const row = parseReport(fixture());
  const runs = [1000, 2500, 9000].map(lcp => ({ id: "home", profile: "mobile", ...row,
    metrics: { ...row.metrics, lcp, fcp: 9999, ttfb: 9999, tbt: 9999 } }));
  const result = summarize(runs);
  assert.equal(result.exitCode, 0);
  assert.equal(result.groups[0].metrics.lcp, 2500);
  assert.equal(result.groups[0].samples, 3);
  assert.deepEqual(result.groups[0].diagnostics, ["fcp", "ttfb"]);
  assert.equal(result.fieldInp, "not-measured");
  runs[0].metrics.cls = 0.2; runs[1].metrics.cls = 0.2;
  assert.equal(summarize(runs).exitCode, 2);
});

test("infrastructure failure takes precedence without hiding budget failures or missing samples", () => {
  const row = parseReport(fixture()); row.metrics.lcp = 3000;
  const result = summarize([{ id: "home", profile: "mobile", ...row },
    { id: "home", profile: "mobile", failure: "timeout" }]);
  assert.equal(result.exitCode, 1);
  assert.equal(result.groups[0].failures, 1);
  assert.equal(result.groups[0].attempts, 2);
  assert.deepEqual(result.groups[0].budgetFailures, ["lcp"]);
});

test("CLI rejects credentials, foreign routes, duplicate labels and invalid bounds", () => {
  const base = ["--base-url", "https://example.invalid", "--server-cache", "unknown", "--connection", "mobile-5g"];
  assert.equal(parseOptions(base).repeats, 3);
  for (const extra of [["--repeats", "0"], ["--profile", "tablet"], ["--timeout-ms", "1"],
    ["--base-url", "https://user:SECRET@example.invalid"], ["--connection", "SECRET"]]) {
    assert.throws(() => parseOptions([...base, ...extra]));
  }
  assert.throws(() => parseOptions(base, [{ id: "home", path: "https://foreign.invalid/SECRET" }]));
  assert.throws(() => parseOptions(base, [{ id: "home", path: "/" }, { id: "home", path: "/faq" }]));
});

test("rendered HTML escapes safe metadata and includes sample counts and diagnostic status", () => {
  const result = summarize([{ id: "home", profile: "mobile", ...parseReport(fixture()) }]);
  const html = renderHtml({ ...result, metadata: { connection: "<test>" } });
  assert.ok(html.includes("&lt;test&gt;"));
  assert.ok(html.includes("not-measured"));
  assert.ok(html.includes("2500"));
  assert.equal(html.includes("SECRET"), false);
});

test("CLI infrastructure failure writes redacted artifacts and exits 1", async () => {
  const { mkdtemp, readFile, rm, writeFile } = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const { spawnSync } = await import("node:child_process");
  const dir = await mkdtemp(join(tmpdir(), "performance-test-"));
  try {
    await writeFile(join(dir, "routes.json"), JSON.stringify([{ id: "event", path: "/private-SECRET?token=SECRET" }]));
    const child = spawnSync(process.execPath, ["script/performance/measure.mjs", "--base-url", "https://example.invalid",
      "--profile", "desktop", "--repeats", "1", "--chrome-path", "/nonexistent/chrome",
      "--connection", "unknown", "--server-cache", "unknown", "--urls", join(dir, "routes.json"), "--output", dir],
    { encoding: "utf8", timeout: 10000 });
    assert.equal(child.status, 1);
    const json = JSON.parse(await readFile(join(dir, "summary.json"), "utf8"));
    assert.equal(json.groups[0].failures, 1);
    assert.equal(json.runs[0].failure, "browser-or-transport");
    for (const name of ["summary.json", "runs.csv", "summary.html"]) {
      const content = await readFile(join(dir, name), "utf8");
      assert.equal(content.includes("SECRET"), false);
      assert.equal(content.includes("example.invalid"), false);
    }
    assert.equal((child.stdout + child.stderr).includes("SECRET"), false);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

// Chrome and audit are the external, expensive boundaries; keep the worker lifecycle real.
test("worker returns selected metrics when Chrome cleanup returns void", async () => {
  const { runNavigation } = await import("../../script/performance/worker.mjs");
  const row = await runNavigation({ url: "https://example.invalid", profile: "mobile", userDataDir: "/unused" }, {
    createBrowser: () => ({ pid: 123, async launch() {}, kill() {} }),
    audit: async () => ({ lhr: fixture() })
  });
  assert.equal(row.metrics.lcp, 2500);
});

test("desktop navigation resolves to desktop UA with direct unthrottled settings", async () => {
  const { runNavigation } = await import("../../script/performance/worker.mjs");
  const { initializeConfig } = await import("lighthouse/core/config/config.js");
  let settings;
  await runNavigation({ url: "https://example.invalid", profile: "desktop", userDataDir: "/unused" }, {
    createBrowser: () => ({ pid: 123, async launch() {}, kill() {} }),
    audit: async (_url, _flags, config) => {
      const resolved = await initializeConfig("navigation", config);
      settings = resolved.resolvedConfig.settings;
      return { lhr: fixture() };
    }
  });
  assert.equal(settings.emulatedUserAgent.includes("Android"), false);
  assert.equal(settings.throttlingMethod, "devtools");
  assert.equal(settings.throttling.requestLatencyMs, 0);
  assert.equal(settings.throttling.downloadThroughputKbps, 0);
  assert.equal(settings.screenEmulation.width, 1350);
});

test("a bounded navigation deadline is infrastructure timeout, not a metric failure", async () => {
  const { measureOne } = await import("../../script/performance/measure.mjs");
  const row = await measureOne({ url: "https://example.invalid/private?token=SECRET", profile: "mobile" }, 1);
  assert.deepEqual(row, { failure: "timeout" });
});

async function browserWithoutDebugger() {
  const fs = await import("node:fs/promises");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const dir = await fs.mkdtemp(join(tmpdir(), "performance-startup-"));
  const executable = join(dir, "browser-fixture");
  const pidFile = join(dir, "pids.json");
  await fs.writeFile(executable, `#!${process.execPath}\nconst fs = require("node:fs");
const { spawn } = require("node:child_process");
const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { stdio: "ignore" });
fs.writeFileSync(${JSON.stringify(pidFile)}, JSON.stringify([process.pid, child.pid]));
setInterval(() => {}, 1000);\n`, { mode: 0o700 });
  const readPids = async () => JSON.parse(await fs.readFile(pidFile, "utf8"));
  return { dir, executable, readPids, async cleanup() {
    for (const pid of await readPids().catch(() => [])) {
      try { process.kill(-pid, "SIGKILL"); } catch { /* Already stopped. */ }
      try { process.kill(pid, "SIGKILL"); } catch { /* Already stopped. */ }
    }
    await fs.rm(dir, { recursive: true, force: true });
  } };
}

async function assertProcessesStopped(pids) {
  const { setTimeout } = await import("node:timers/promises");
  const alive = pid => { try { process.kill(pid, 0); return true; } catch { return false; } };
  for (let attempt = 0; attempt < 40 && pids.some(alive); attempt++) await setTimeout(25);
  assert.deepEqual(pids.filter(alive), [], "browser process and same-group descendant must both stop");
}

test("readiness rejection stops an actually spawned browser process group", async () => {
  const browser = await browserWithoutDebugger();
  const worker = await import("../../script/performance/worker.mjs");
  try {
    const fastFailure = { connectionPollInterval: 50, maxConnectionRetries: 20 };
    const result = await worker.runNavigation({ chromePath: browser.executable, userDataDir: browser.dir,
      url: "https://example.invalid", profile: "mobile" }, {
      createBrowser: (options, onSpawn) => worker.createOwnedBrowser({ ...options, ...fastFailure }, onSpawn)
    });
    assert.deepEqual(result, { failure: "browser-or-transport" });
    await assertProcessesStopped(await browser.readPids());
  } finally { await browser.cleanup(); }
});

test("allowed 10-second deadline stops a browser group while debugger startup is pending", async () => {
  const browser = await browserWithoutDebugger();
  const { measureOne } = await import("../../script/performance/measure.mjs");
  try {
    const result = await measureOne({ chromePath: browser.executable,
      url: "https://example.invalid", profile: "mobile" }, 10000);
    assert.deepEqual(result, { failure: "timeout" });
    await assertProcessesStopped(await browser.readPids());
  } finally { await browser.cleanup(); }
});
