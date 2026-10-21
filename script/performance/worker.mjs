// A disposable process owns one fresh Chrome profile. Raw LHR exists only in memory.
import lighthouse from "lighthouse";
import { access } from "node:fs/promises";
import { constants } from "node:fs";
import { Launcher } from "chrome-launcher";
import { spawn } from "node:child_process";
import { parseReport, profiles } from "./results.mjs";

let chrome, stopping = false;
// Launcher and ModuleOverrides.spawn are public in chrome-launcher 1.2.1.
// Own the instance before readiness, and publish our spawned PID before its debugger wait.
export function createOwnedBrowser(options, onSpawn = () => {}) {
  return new Launcher(options, { spawn: (...args) => {
    if (stopping) throw new Error("stopping");
    const subprocess = spawn(...args);
    try { onSpawn(subprocess.pid); } catch { /* Disconnect cleanup still owns this process. */ }
    return subprocess;
  } });
}
const cleanup = async () => { try { if (chrome) await chrome.kill(); } catch { /* Already stopped. */ } };
export async function runNavigation({ url, profile, chromePath, userDataDir }, { createBrowser = createOwnedBrowser, audit = lighthouse, onLaunch = () => {} } = {}) {
  let result;
  try {
    if (chromePath) await access(chromePath, constants.X_OK);
    chrome = createBrowser({ chromePath, userDataDir, logLevel: "silent", handleSIGINT: false,
      chromeFlags: ["--headless=new", "--no-first-run", "--no-default-browser-check", "--disable-extensions"] }, onLaunch);
    await chrome.launch();
    const { lhr } = await audit(url, { port: chrome.port, logLevel: "silent" }, {
      extends: "lighthouse:default",
      settings: { ...profiles[profile], onlyCategories: ["performance"], throttlingMethod: "devtools",
        disableStorageReset: false, emulatedUserAgent: true, maxWaitForLoad: 45000 }
    });
    result = parseReport(lhr);
  } catch {
    result = { failure: "browser-or-transport" };
  } finally {
    await cleanup();
  }
  return result;
}

if (process.send) {
  const shutdown = async () => { stopping = true; await cleanup(); process.exit(1); };
  process.on("disconnect", shutdown);
  process.on("SIGTERM", shutdown);
  process.once("message", async input => {
    const result = await runNavigation(input, { onLaunch: chromePid => process.send({ chromePid }) });
    process.send({ result }, () => process.exit(0));
  });
}
