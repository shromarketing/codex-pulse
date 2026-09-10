importScripts("usage-parser.js");

const PULSE_ORIGIN = "http://127.0.0.1:37421";
const SYNC_ALARM = "codex-pulse-claude-sync";

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create(SYNC_ALARM, { periodInMinutes: 2 });
});

chrome.runtime.onStartup.addListener(() => {
  chrome.alarms.create(SYNC_ALARM, { periodInMinutes: 2 });
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === SYNC_ALARM) runBackgroundSync();
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === "complete" && tab.url?.startsWith("https://claude.ai/")) {
    runBackgroundSync(tabId);
  }
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "pair") {
    pair(message.code)
      .then((result) => sendResponse({ ok: true, ...result }))
      .catch((error) => sendResponse({ ok: false, error: error.message }));
    return true;
  }
  if (message?.type === "sync") {
    syncNow()
      .then((result) => sendResponse({ ok: true, ...result }))
      .catch((error) => sendResponse({ ok: false, error: error.message }));
    return true;
  }
  if (message?.type === "status") {
    getStatus().then(sendResponse);
    return true;
  }
  if (message?.type === "disconnect") {
    chrome.storage.local.remove(["pulseToken", "lastSync", "lastError"]).then(() => sendResponse({ ok: true }));
    return true;
  }
});

async function pair(code) {
  const normalized = String(code || "").trim().toUpperCase();
  if (!/^[A-Z2-9]{8}$/.test(normalized)) throw new Error("Enter the 8-character code from Codex Pulse.");
  const response = await fetch(`${PULSE_ORIGIN}/v1/pair`, {
    method: "POST",
    headers: { "X-Codex-Pulse-Code": normalized }
  });
  if (response.status === 429) throw new Error("Too many attempts. Create a new code or wait one minute.");
  if (!response.ok) throw new Error("The pairing code is invalid or expired.");
  const payload = await response.json();
  if (!payload.token) throw new Error("Codex Pulse returned no pairing token.");
  await chrome.storage.local.set({ pulseToken: payload.token, lastError: null });
  return syncNow();
}

async function runBackgroundSync(preferredTabId) {
  try {
    await syncNow(preferredTabId);
  } catch (error) {
    await chrome.storage.local.set({
      lastError: error?.message || String(error || "Unknown error")
    });
  }
}

async function getStatus() {
  const stored = await chrome.storage.local.get(["pulseToken", "lastSync", "lastError"]);
  return {
    ok: true,
    paired: Boolean(stored.pulseToken),
    lastSync: stored.lastSync || null,
    lastError: stored.lastError || null
  };
}

async function syncNow(preferredTabId) {
  const stored = await chrome.storage.local.get(["pulseToken"]);
  if (!stored.pulseToken) throw new Error("Pair the extension with Codex Pulse first.");

  let tabId = preferredTabId;
  if (!tabId) {
    const tabs = await chrome.tabs.query({ url: ["https://claude.ai/*"] });
    const selected = tabs.find((tab) => tab.active) || tabs[0];
    tabId = selected?.id;
  }
  if (!tabId) throw new Error("Open claude.ai in this Chrome profile and sign in.");

  const injection = await chrome.scripting.executeScript({
    target: { tabId },
    world: "MAIN",
    func: async () => {
      const requestJSON = async (url) => {
        const response = await fetch(url, {
          credentials: "include",
          headers: { Accept: "application/json" },
          cache: "no-store"
        });
        if (!response.ok) throw new Error(`Claude returned HTTP ${response.status}`);
        return response.json();
      };

      const organizations = await requestJSON("/api/organizations");
      const organization = organizations.find((item) => item.capabilities?.includes("chat"))
        || organizations.find((item) => !(item.capabilities?.length === 1 && item.capabilities[0] === "api"))
        || organizations[0];
      if (!organization?.uuid) throw new Error("No Claude organization was found.");

      const usage = await requestJSON(`/api/organizations/${encodeURIComponent(organization.uuid)}/usage`);
      let account = null;
      try { account = await requestJSON("/api/account"); } catch (_) {}

      const membership = account?.memberships?.find((item) => item.organization?.uuid === organization.uuid)
        || account?.memberships?.[0]
        || null;
      return {
        usage,
        plan: membership ? {
          rateLimitTier: membership.organization?.rate_limit_tier || null,
          billingType: membership.organization?.billing_type || null,
          seatTier: membership.seat_tier || null
        } : null
      };
    }
  });

  const claudeResult = injection?.[0]?.result;
  const payload = claudeResult ? {
    schemaVersion: 1,
    capturedAt: new Date().toISOString(),
    windows: PulseUsageParser.extractClaudeQuotaWindows(claudeResult.usage),
    plan: claudeResult.plan || null
  } : null;
  if (!payload?.windows?.length) throw new Error("Claude returned no quota windows.");
  const response = await fetch(`${PULSE_ORIGIN}/v1/claude/usage`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${stored.pulseToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });
  if (response.status === 401) {
    await chrome.storage.local.remove(["pulseToken"]);
    throw new Error("Pairing expired. Create a new code in Codex Pulse.");
  }
  if (!response.ok) throw new Error(`Codex Pulse rejected the update (${response.status}).`);

  const lastSync = new Date().toISOString();
  await chrome.storage.local.set({ lastSync, lastError: null });
  return { paired: true, lastSync, windows: payload.windows.length };
}

self.addEventListener("unhandledrejection", (event) => {
  const message = event.reason?.message || String(event.reason || "Unknown error");
  chrome.storage.local.set({ lastError: message });
});
