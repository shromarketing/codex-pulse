import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const root = fileURLToPath(new URL("../", import.meta.url));
const popup = readFileSync(`${root}/BrowserExtension/PulseConnector/popup.js`, "utf8");
const html = readFileSync(`${root}/BrowserExtension/PulseConnector/popup.html`, "utf8");
const parserSource = readFileSync(`${root}/BrowserExtension/PulseConnector/usage-parser.js`, "utf8");

for (const id of ["pairing", "connected"]) {
  if (!html.includes(`id="${id}"`)) throw new Error(`Missing structural popup block: ${id}`);
  if (new RegExp(`^\\s*${id}:\\s*[\"']`, "m").test(popup)) {
    throw new Error(`Localization key must not overwrite structural block #${id}`);
  }
}

for (const id of ["code", "pairButton", "syncButton", "disconnectButton"]) {
  if (!html.includes(`id="${id}"`)) throw new Error(`Missing popup control: ${id}`);
}

const sandbox = {};
sandbox.globalThis = sandbox;
vm.runInNewContext(parserSource, sandbox, { filename: "usage-parser.js" });
const parse = sandbox.PulseUsageParser?.extractClaudeQuotaWindows;
if (typeof parse !== "function") throw new Error("Claude usage parser was not loaded.");

const modernWindows = parse({
  five_hour: { utilization: 12, resets_at: "2026-08-12T12:00:00Z" },
  seven_day: { utilization: 66, resets_at: "2026-08-15T12:00:00Z" },
  limits: [
    {
      kind: "weekly_scoped",
      group: "weekly",
      percent: 74,
      resets_at: "2026-08-15T12:00:00Z",
      is_active: false,
      scope: { model: { id: "claude-fable", display_name: "Fable" } }
    },
    {
      kind: "weekly_scoped",
      group: "weekly",
      percent: 66,
      resets_at: "2026-08-15T12:00:00Z",
      scope: { model: { id: "all-models", display_name: "All models" } }
    }
  ],
  seven_day_fable: { utilization: 73, resets_at: "2026-08-15T12:00:00Z" }
});

const fableWindows = modernWindows.filter((item) => item.title === "Fable");
if (modernWindows.length !== 3) throw new Error(`Expected session, weekly and Fable windows; got ${modernWindows.length}.`);
if (fableWindows.length !== 1) throw new Error("Modern and legacy Fable limits were not deduplicated.");
if (fableWindows[0].utilization !== 74) throw new Error("The current scoped Fable limit must win over the legacy field.");
if (modernWindows.some((item) => item.title === "All models")) throw new Error("Generic All models limit must not duplicate weekly usage.");

const legacyFable = parse({ seven_day_fable: { utilization: 41, resets_at: null } });
if (legacyFable.length !== 1 || legacyFable[0].title !== "Fable") {
  throw new Error("Legacy Fable fallback is broken.");
}

console.log("Pulse Connector popup and Claude quota parser checks passed.");
