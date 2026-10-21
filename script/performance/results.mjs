import { parseArgs } from "node:util";

export const profiles = {
  mobile: {
    formFactor: "mobile", screenEmulation: { width: 412, height: 823, deviceScaleFactor: 1.75, mobile: true, disabled: false },
    throttling: { rttMs: 150, throughputKbps: 1638.4, requestLatencyMs: 562.5, downloadThroughputKbps: 1474.5600000000002, uploadThroughputKbps: 675, cpuSlowdownMultiplier: 4 }
  },
  desktop: {
    formFactor: "desktop", screenEmulation: { width: 1350, height: 940, deviceScaleFactor: 1, mobile: false, disabled: false },
    throttling: { rttMs: 40, throughputKbps: 10240, requestLatencyMs: 0, downloadThroughputKbps: 0, uploadThroughputKbps: 0, cpuSlowdownMultiplier: 1 }
  }
};
export const budgets = { lcp: 2500, cls: 0.1 };
const diagnosticTargets = { fcp: 1800, ttfb: 800 };
export const defaultRoutes = [{ id: "home", path: "/" }, { id: "news", path: "/news" }, { id: "faq", path: "/faq" }];
const validNumber = value => typeof value === "number" && Number.isFinite(value) && value >= 0;

const safeUserAgent = value => typeof value === "string" && value.length <= 300 && /^(?:Mozilla\/5\.0 |HeadlessChrome\/)[A-Za-z0-9 (),.;_\/+-]+$/.test(value) ? value : "unknown";

export function parseReport(report) {
  if (report?.runtimeError) return { failure: "navigation" };
  const m = report?.audits?.metrics?.details?.items?.[0] ?? {};
  const metrics = { lcp: m.observedLargestContentfulPaint, fcp: m.observedFirstContentfulPaint,
    ttfb: m.timeToFirstByte, cls: m.observedCumulativeLayoutShift, tbt: m.totalBlockingTime };
  if (!Object.values(metrics).every(validNumber)) return { failure: "invalid-metrics" };
  const total = report.audits["resource-summary"]?.details?.items?.find(item => item.resourceType === "total");
  // Allow only browser-version metadata, never free-form page, network or warning text.
  const browser = safeUserAgent(report.environment?.hostUserAgent);
  const version = /^\d+\.\d+\.\d+$/.test(report.lighthouseVersion) ? report.lighthouseVersion : "unknown";
  return { metrics, browser, emulatedUserAgent: safeUserAgent(report.environment?.networkUserAgent), lighthouse: version,
    resources: { transferBytes: validNumber(total?.transferSize) ? total.transferSize : null,
      requests: validNumber(total?.requestCount) ? total.requestCount : null } };
}

export function summarize(runs) {
  const groups = [];
  for (const key of new Set(runs.map(row => `${row.id}:${row.profile}`))) {
    const rows = runs.filter(row => `${row.id}:${row.profile}` === key);
    const good = rows.filter(row => !row.failure);
    const median = values => {
      values.sort((a, b) => a - b);
      const mid = Math.floor(values.length / 2);
      return values.length % 2 ? values[mid] : (values[mid - 1] + values[mid]) / 2;
    };
    const metrics = Object.fromEntries(["lcp", "fcp", "ttfb", "cls", "tbt"].map(metric =>
      [metric, good.length ? median(good.map(row => row.metrics[metric])) : null]));
    groups.push({ id: rows[0].id, profile: rows[0].profile, attempts: rows.length,
      samples: good.length, failures: rows.length - good.length, metrics,
      budgetFailures: Object.keys(budgets).filter(metric => metrics[metric] > budgets[metric]),
      diagnostics: Object.keys(diagnosticTargets).filter(metric => metrics[metric] > diagnosticTargets[metric]) });
  }
  const exitCode = !runs.length || runs.some(row => row.failure) ? 1 : groups.some(group => group.budgetFailures.length) ? 2 : 0;
  return { exitCode, budgets, diagnosticTargets, fieldInp: "not-measured", groups };
}

export function parseOptions(args, routes = defaultRoutes) {
  const { values } = parseArgs({ args, options: Object.fromEntries(
    ["base-url", "profile", "urls", "repeats", "timeout-ms", "output", "server-cache", "connection", "chrome-path", "release"].map(name => [name, { type: "string" }])) });
  const base = new URL(values["base-url"] ?? "https://stuttgart-live.de");
  if (!['http:', 'https:'].includes(base.protocol) || base.username || base.password || base.pathname !== "/" || base.search || base.hash) throw new Error("invalid-base");
  const profileNames = (values.profile ?? "mobile,desktop").split(",");
  if (!profileNames.length || profileNames.some(name => !Object.hasOwn(profiles, name)) || new Set(profileNames).size !== profileNames.length) throw new Error("invalid-profile");
  if (values.release && !/^[a-f0-9]{7,40}$/.test(values.release)) throw new Error("invalid-release");
  const repeats = Number(values.repeats ?? 3), timeoutMs = Number(values["timeout-ms"] ?? 120000);
  if (!Number.isInteger(repeats) || repeats < 1 || repeats > 10 || !Number.isInteger(timeoutMs) || timeoutMs < 10000 || timeoutMs > 300000) throw new Error("invalid-bounds");
  if (!["cold", "warm", "mixed", "unknown"].includes(values["server-cache"]) ||
      !["mobile-5g", "fixed", "github-runner", "loopback", "unknown"].includes(values.connection)) throw new Error("metadata-required");
  if (!Array.isArray(routes) || routes.length < 1 || routes.length > 50 || new Set(routes.map(row => row.id)).size !== routes.length) throw new Error("invalid-routes");
  for (const route of routes) {
    if (!/^[a-z][a-z0-9-]{0,39}$/.test(route.id) || typeof route.path !== "string" || !route.path.startsWith("/") || route.path.startsWith("//")) throw new Error("invalid-route");
    const url = new URL(route.path, base);
    if (url.origin !== base.origin || url.username || url.password || url.hash) throw new Error("invalid-route");
  }
  return { base: base.origin, profiles: profileNames, repeats, timeoutMs, routes,
    urlsFile: values.urls, output: values.output ?? "output/performance/latest",
    release: values.release ?? "unknown", serverCache: values["server-cache"], connection: values.connection, chromePath: values["chrome-path"] };
}

const escapeHtml = value => String(value).replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[character]));
export function renderHtml(report) {
  return `<!doctype html><html lang="de"><meta charset="utf-8"><title>Performance-Diagnose</title>
<style>body{font:16px system-ui;margin:2rem;max-width:75rem}table{border-collapse:collapse}td,th{padding:.6rem;border:1px solid #aaa;text-align:left}pre{white-space:pre-wrap}</style>
<h1>Performance-Diagnose</h1><p>Labormediane, keine Feldbewertung. Feld-INP: ${escapeHtml(report.fieldInp)}. Drei Läufe belegen kein „Good“.</p>
<p>Exit ${report.exitCode}: 0 Budgets eingehalten; 1 Infrastruktur/Transport; 2 Budgetüberschreitung. FCP/TTFB sind Diagnoseziele; TBT ist separat berichtet.</p>
<pre>${escapeHtml(JSON.stringify(report.metadata, null, 2))}</pre>
<table><tr><th>Route</th><th>Profil</th><th>Samples/Versuche</th><th>Fehler</th><th>LCP/FCP/TTFB ms</th><th>CLS</th><th>TBT ms</th><th>Budgets / Diagnose</th></tr>
${report.groups.map(group => `<tr><td>${escapeHtml(group.id)}</td><td>${escapeHtml(group.profile)}</td><td>${group.samples}/${group.attempts}</td><td>${group.failures}</td><td>${group.metrics.lcp} / ${group.metrics.fcp} / ${group.metrics.ttfb}</td><td>${group.metrics.cls}</td><td>${group.metrics.tbt}</td><td>${group.budgetFailures.join(", ")} / ${group.diagnostics.join(", ")}</td></tr>`).join("\n")}</table></html>`;
}
