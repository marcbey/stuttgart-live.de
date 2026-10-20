// A disposable process owns one fresh Chrome profile. Raw LHR exists only in memory.
import lighthouse from "lighthouse";
import { access } from "node:fs/promises";
import { constants } from "node:fs";
import { launch } from "chrome-launcher";
import { parseReport, profiles } from "./results.mjs";

let chrome;
const cleanup = async () => { try { if (chrome) await chrome.kill(); } catch { /* Already stopped. */ } };
export async function runNavigation({ url, profile, chromePath, userDataDir }, { launchBrowser = launch, audit = lighthouse, onLaunch = () => {} } = {}) {
  let result;
  try {
    if (chromePath) await access(chromePath, constants.X_OK);
    chrome = await launchBrowser({ chromePath, userDataDir, logLevel: "silent", handleSIGINT: false,
      chromeFlags: ["--headless=new", "--no-first-run", "--no-default-browser-check", "--disable-extensions"] });
    onLaunch(chrome.pid);
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
  process.on("disconnect", async () => { await cleanup(); process.exit(1); });
  process.once("message", async input => {
    const result = await runNavigation(input, { onLaunch: chromePid => process.send({ chromePid }) });
    process.send({ result }, () => process.exit(0));
  });
}
