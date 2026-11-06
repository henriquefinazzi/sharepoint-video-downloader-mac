// Tells the background script whether this page is a SharePoint/Stream video,
// so the toolbar button is only clickable there. Runs on SharePoint hosts only.
(() => {
  const api = globalThis.browser ?? globalThis.chrome;
  const isTopFrame = window === window.top;

  function looksLikeVideoPage() {
    if (/\/stream\.aspx/i.test(location.pathname)) return true;
    if (/microsoftstream\.com\/video\//i.test(location.href)) return true;
    if (document.querySelector("video")) return true;
    for (const script of document.scripts) {
      const text = script.textContent;
      if (text && text.includes('".transformUrl"')) return true;
    }
    return false;
  }

  let lastReported = null;
  let lastUrl = location.href;

  function report() {
    const isVideo = looksLikeVideoPage();
    // Frames only report positives (an embedded player); the top frame owns "not a video".
    if (!isVideo && !isTopFrame) return;
    if (isVideo === lastReported) return;
    lastReported = isVideo;
    api.runtime.sendMessage({ type: "videoPage", isVideo }).catch(() => {});
  }

  report();

  // SharePoint is a single-page app and the player loads late: re-check on
  // URL changes and for a while after each one.
  let checksLeft = 20;
  setInterval(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      lastReported = null;
      checksLeft = 20;
    }
    if (checksLeft > 0) {
      checksLeft -= 1;
      report();
    }
  }, 1000);
})();
