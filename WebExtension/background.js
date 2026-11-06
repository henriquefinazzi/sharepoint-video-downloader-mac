// SharePoint Video Downloader — Safari background script.
//
// On toolbar click: read SharePoint's own video metadata from the page,
// turn it into a DASH manifest URL, and hand it to the Mac app via
// native messaging. The app runs yt-dlp + ffmpeg to download and merge.

const api = globalThis.browser ?? globalThis.chrome;
// Safari ignores this ID and always delivers native messages to the extension's
// own containing app, so it doesn't need to match the bundle ID.
const APP_ID = "SPVideoDownloader";
const SUPPORTED_HOST = /(^|\.)(sharepoint\.com|svc\.ms|microsoftstream\.com)$/i;

function isSupported(url) {
  try {
    return SUPPORTED_HOST.test(new URL(url).hostname);
  } catch {
    return false;
  }
}

async function showBadge(tabId, text, color) {
  try {
    await api.action.setBadgeBackgroundColor({ tabId, color });
    await api.action.setBadgeText({ tabId, text });
    setTimeout(() => api.action.setBadgeText({ tabId, text: "" }).catch(() => {}), 5000);
  } catch {
    // Badges are cosmetic; ignore failures.
  }
}

function alertInTab(tabId, message) {
  return api.scripting
    .executeScript({ target: { tabId }, func: (m) => alert(m), args: [message] })
    .catch(() => {});
}

// ---- Button availability ---------------------------------------------------
// Safari can't hide a toolbar button per page, so it's disabled (greyed out)
// everywhere and enabled per tab when content.js reports a video page.

// Every size so Safari never upscales a small image on Retina screens.
const TOOLBAR_SIZES = [16, 19, 32, 38, 48, 64, 96, 128];
const iconSet = (prefix) =>
  Object.fromEntries(TOOLBAR_SIZES.map((s) => [s, `images/${prefix}-${s}.png`]));
const ICON_IDLE = iconSet("toolbar");
const ICON_ACTIVE = iconSet("toolbar-active");

function setTabState(tabId, isVideo) {
  if (isVideo) {
    api.action.enable(tabId).catch(() => {});
    api.action.setIcon({ tabId, path: ICON_ACTIVE }).catch(() => {});
    api.action.setTitle({ tabId, title: "Download this video" }).catch(() => {});
  } else {
    api.action.disable(tabId).catch(() => {});
    api.action.setIcon({ tabId, path: ICON_IDLE }).catch(() => {});
    api.action.setTitle({ tabId, title: "Open a SharePoint video to download it" }).catch(() => {});
  }
}

api.action.disable().catch(() => {});

api.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === "loading" && changeInfo.url) setTabState(tabId, false);
});

api.runtime.onMessage.addListener((message, sender) => {
  const tabId = sender.tab?.id;
  if (message?.type !== "videoPage" || tabId == null) return;
  setTabState(tabId, Boolean(message.isVideo));
});

// ---- Functions injected into the page -------------------------------------

// Runs in the page's own JavaScript world, where window.g_fileInfo lives.
function readFromPageGlobals() {
  const info = window.g_fileInfo;
  if (!info) return null;
  return info[".transformUrl"] || info[".providerCdnTransformUrl"] || null;
}

// Fallback for the isolated world: find the same value in inline <script> text.
function readFromInlineScripts() {
  const texts = Array.from(document.scripts, (s) => s.textContent || "");
  for (const key of ["transformUrl", "providerCdnTransformUrl"]) {
    const re = new RegExp('"\\.' + key + '"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"');
    for (const text of texts) {
      const match = text.match(re);
      if (match) {
        try {
          return JSON.parse('"' + match[1] + '"');
        } catch {
          // Malformed escape; keep looking.
        }
      }
    }
  }
  return null;
}

// ---- Extraction ------------------------------------------------------------

function firstResult(results) {
  for (const r of results ?? []) {
    if (typeof r?.result === "string" && r.result) return r.result;
  }
  return null;
}

async function findTransformUrl(tabId) {
  try {
    const results = await api.scripting.executeScript({
      target: { tabId, allFrames: true },
      world: "MAIN",
      func: readFromPageGlobals,
    });
    const found = firstResult(results);
    if (found) return found;
  } catch (e) {
    console.debug("Page-world injection unavailable, falling back:", e);
  }

  const results = await api.scripting.executeScript({
    target: { tabId, allFrames: true },
    func: readFromInlineScripts,
  });
  return firstResult(results);
}

function buildManifestUrl(transformUrl) {
  const url = new URL(transformUrl);
  if (!/\/transform\//.test(url.pathname)) return null;
  url.pathname = url.pathname.replace(/\/transform\/.*$/, "/transform/videomanifest");
  url.searchParams.set("part", "index");
  url.searchParams.set("format", "dash");
  const text = url.toString();
  const anchor = "format=dash";
  return text.slice(0, text.indexOf(anchor) + anchor.length);
}

// ---- Click handler ---------------------------------------------------------

api.action.onClicked.addListener(async (tab) => {
  if (!tab?.id) return;

  if (!isSupported(tab.url)) {
    await alertInTab(tab.id, "Open a SharePoint or Microsoft Stream video page first.");
    return;
  }

  try {
    const transformUrl = await findTransformUrl(tab.id);
    const manifestUrl = transformUrl && buildManifestUrl(transformUrl);
    if (!manifestUrl) {
      await showBadge(tab.id, "!", "#d93025");
      await alertInTab(
        tab.id,
        "Couldn't find the video on this page. Wait for the player to finish loading and try again."
      );
      return;
    }

    const reply = await api.runtime.sendNativeMessage(APP_ID, {
      action: "download",
      url: manifestUrl,
      title: tab.title || "SharePoint Video",
    });

    if (reply?.ok) {
      await showBadge(tab.id, "↓", "#1a73e8");
    } else {
      await showBadge(tab.id, "!", "#d93025");
      await alertInTab(tab.id, "The downloader app didn't accept the video: " + (reply?.error ?? "no reply"));
    }
  } catch (e) {
    await showBadge(tab.id, "!", "#d93025");
    await alertInTab(tab.id, "SharePoint Video Downloader error: " + (e?.message ?? e));
  }
});
