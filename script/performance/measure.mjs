#!/usr/bin/env node
import { fork, spawnSync } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseOptions, profiles, summarize, renderHtml } from "./results.mjs";

export async function measureOne(input, timeoutMs) {
  const userDataDir = await fs.mkdtemp(path.join(os.tmpdir(), "stgt-performance-"));
  const child = fork(new URL("./worker.mjs", import.meta.url), [], { silent: true });
  // Drain/discard all dependency output: it can contain visited URLs or network errors.
  child.stdout.resume(); child.stderr.resume();
  let chromePid, result, timedOut = false;
  const killChrome = () => {
    if (!chromePid) return;
    try {
      if (process.platform === "win32") spawnSync("taskkill", ["/pid", String(chromePid), "/T", "/F"], { stdio: "ignore" });
      else process.kill(-chromePid, "SIGKILL");
    } catch { /* Already stopped. */ }
  };
  try {
    return await new Promise(resolve => {
      const timer = setTimeout(() => { timedOut = true; killChrome(); child.kill("SIGKILL"); }, timeoutMs);
      child.on("message", message => {
        if (Number.isInteger(message.chromePid)) chromePid = message.chromePid;
        if (message.result) result = message.result;
      });
      child.once("error", () => { clearTimeout(timer); resolve({ failure: "worker" }); });
      child.once("exit", code => {
        clearTimeout(timer); killChrome();
        resolve(timedOut ? { failure: "timeout" } : code === 0 && result ? result : { failure: "worker" });
      });
      child.send({ ...input, userDataDir });
    });
  } finally {
    killChrome();
    await fs.rm(userDataDir, { recursive: true, force: true });
  }
}

async function main() {
  let options;
  try {
    const initial = parseOptions(process.argv.slice(2));
    const routes = initial.urlsFile ? JSON.parse(await fs.readFile(initial.urlsFile, "utf8")) : undefined;
    options = parseOptions(process.argv.slice(2), routes);
  } catch {
    console.error("Konfiguration ungültig: Basis-URL ohne Zugangsdaten, sichere Routenliste und --connection/--server-cache angeben. Siehe README.");
    return 1;
  }
  // Never copy base URLs, paths, queries, output paths or environment variables to the report.
  const metadata = { createdAt: new Date().toISOString(), connection: options.connection,
    serverCache: options.serverCache, release: options.release, node: process.version, platform: process.platform,
    browserCache: "fresh-profile-and-storage-reset-per-navigation", throttlingMethod: "devtools",
    profiles: Object.fromEntries(options.profiles.map(name => [name, profiles[name]])),
    fieldInpTargetMs: 200, note: "Initial anonymous navigation only; no consent or interactions. Historical DSL audit is not a paired baseline for mobile-5g." };
  const runs = [];
  await fs.mkdir(options.output, { recursive: true, mode: 0o700 });
  const write = async () => {
    const report = { schemaVersion: 1, metadata, ...summarize(runs), runs };
    await fs.writeFile(path.join(options.output, "summary.json"), JSON.stringify(report, null, 2), { mode: 0o600 });
    const columns = ["id", "profile", "run", "failure", "lcp", "fcp", "ttfb", "cls", "tbt", "transferBytes", "requests"];
    const csv = [columns.join(","), ...runs.map(row => columns.map(column => row[column] ?? row.metrics?.[column] ?? row.resources?.[column] ?? "").join(","))].join("\n") + "\n";
    await fs.writeFile(path.join(options.output, "runs.csv"), csv, { mode: 0o600 });
    await fs.writeFile(path.join(options.output, "summary.html"), renderHtml(report), { mode: 0o600 });
    return report.exitCode;
  };
  await write();
  // Preserve baseline ordering: repetition, profile, route. No parallel requests or retries.
  for (let run = 1; run <= options.repeats; run++) {
    for (const profile of options.profiles) {
      for (const route of options.routes) {
        const start = Date.now();
        const result = await measureOne({ url: new URL(route.path, options.base).href, profile, chromePath: options.chromePath }, options.timeoutMs);
        runs.push({ id: route.id, profile, run, elapsedMs: Date.now() - start, ...result });
        await write();
        console.log(`${route.id} ${profile} ${run}: ${result.failure ?? "measured"}`);
      }
    }
  }
  return write();
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().then(code => { process.exitCode = code; }).catch(() => {
    console.error("Messung oder Artefaktspeicherung fehlgeschlagen (Infrastruktur)."); process.exitCode = 1;
  });
}
