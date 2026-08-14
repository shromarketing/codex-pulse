const ru = navigator.language.toLowerCase().startsWith("ru");
const copy = ru ? {
  subtitle: "Коннектор Claude Web",
  codeLabel: "Код подключения",
  pairButton: "Связать",
  pairHint: "Создайте код в Codex Pulse → Настройки → Сервисы.",
  connectedTitle: "Подключено",
  versionLabel: "Версия коннектора",
  waiting: "Ожидаем первое обновление",
  syncButton: "Обновить",
  disconnectButton: "Отключить этот профиль Chrome",
  privacy: "Из Chrome выходят только проценты лимитов и время сброса. Cookies и чаты остаются в браузере.",
  pairingStatus: "Подключаем…",
  syncingStatus: "Получаем лимиты Claude…",
  syncedStatus: "Данные переданы в Codex Pulse",
  disconnectedStatus: "Профиль отключён"
} : {
  subtitle: "Claude Web Connector",
  codeLabel: "Pairing code",
  pairButton: "Pair",
  pairHint: "Create the code in Codex Pulse → Settings → Services.",
  connectedTitle: "Connected",
  versionLabel: "Connector version",
  waiting: "Waiting for the first update",
  syncButton: "Refresh",
  disconnectButton: "Disconnect this browser profile",
  privacy: "Only quota percentages and reset times leave Chrome. Cookies and chats stay in the browser.",
  pairingStatus: "Pairing…",
  syncingStatus: "Reading Claude limits…",
  syncedStatus: "Updated Codex Pulse",
  disconnectedStatus: "Browser profile disconnected"
};

const localizableIDs = [
  "subtitle", "codeLabel", "pairButton", "pairHint", "connectedTitle",
  "versionLabel", "syncButton", "disconnectButton", "privacy"
];
for (const id of localizableIDs) {
  const value = copy[id];
  const node = document.getElementById(id);
  if (node) node.textContent = value;
}

const pairing = document.getElementById("pairing");
const connected = document.getElementById("connected");
const dot = document.getElementById("dot");
const message = document.getElementById("message");
const lastSync = document.getElementById("lastSync");
const code = document.getElementById("code");
const version = document.getElementById("version");
version.textContent = chrome.runtime.getManifest().version;

document.getElementById("pairButton").addEventListener("click", async () => {
  setMessage(copy.pairingStatus);
  const result = await chrome.runtime.sendMessage({ type: "pair", code: code.value });
  if (!result?.ok) return setMessage(result?.error || "Could not pair");
  setMessage(copy.syncedStatus);
  await refreshStatus();
});

document.getElementById("syncButton").addEventListener("click", async () => {
  setMessage(copy.syncingStatus);
  const result = await chrome.runtime.sendMessage({ type: "sync" });
  if (!result?.ok) return setMessage(result?.error || "Could not refresh");
  setMessage(copy.syncedStatus);
  await refreshStatus();
});

document.getElementById("disconnectButton").addEventListener("click", async () => {
  await chrome.runtime.sendMessage({ type: "disconnect" });
  setMessage(copy.disconnectedStatus);
  await refreshStatus();
});

code.addEventListener("input", () => {
  code.value = code.value.toUpperCase().replace(/[^A-Z2-9]/g, "").slice(0, 8);
});

function setMessage(value) { message.textContent = value || ""; }

async function refreshStatus() {
  const status = await chrome.runtime.sendMessage({ type: "status" });
  pairing.hidden = Boolean(status?.paired);
  connected.hidden = !status?.paired;
  dot.classList.toggle("connected", Boolean(status?.paired));
  if (status?.lastSync) {
    lastSync.textContent = new Intl.DateTimeFormat(ru ? "ru" : "en", {
      hour: "2-digit", minute: "2-digit", day: "numeric", month: "short"
    }).format(new Date(status.lastSync));
  } else {
    lastSync.textContent = copy.waiting;
  }
  if (status?.lastError) setMessage(status.lastError);
}

refreshStatus();
