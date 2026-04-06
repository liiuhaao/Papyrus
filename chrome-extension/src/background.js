const papyrusAPI = globalThis.browser ?? globalThis.chrome;

const MESSAGE_EXTRACT = "PAPYRUS_EXTRACT";
const MESSAGE_FETCH_CURRENT_PDF = "PAPYRUS_FETCH_CURRENT_PDF";
const MESSAGE_SHOW_TOAST = "PAPYRUS_SHOW_TOAST";
const NATIVE_MESSAGE_OPEN_PAPYRUS = "OPEN_PAPYRUS";
const PAPYRUS_HTTP_PORT = 52431;
const CAPTURED_PDF_REQUESTS_STORAGE_KEY = "papyrusCapturedPDFRequests";
const CAPTURED_PDF_RESPONSES_STORAGE_KEY = "papyrusCapturedPDFResponses";
const CAPTURED_PDF_REQUEST_TTL_MS = 15 * 60 * 1000;
const MAX_CAPTURED_PDF_REQUESTS = 24;

const INJECTABLE_FILES = [
  "src/extractors/pdf.js",
  "src/content.js"
];

const TOAST_INJECTABLE_FILES = [
  "src/content.js"
];

function normalizeString(value) {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function normalizeURLForLookup(urlString) {
  try {
    const url = new URL(urlString);
    url.hash = "";
    return url.toString();
  } catch {
    return urlString;
  }
}

function looksLikeDirectPDFURL(urlString) {
  if (!urlString) return false;
  return /\.pdf(?:$|[?#])/i.test(urlString)
    || /openreview\.net\/pdf\?id=/i.test(urlString)
    || /arxiv\.org\/pdf\//i.test(urlString)
    || /\/doi\/(?:pdf|epdf)\//i.test(urlString);
}

function extractDOIFromURL(urlString) {
  if (!urlString) return undefined;
  const match = urlString.match(/10\.\d{4,9}\/[-._;()/:A-Za-z0-9]+/);
  return match ? match[0].toLowerCase() : undefined;
}

function extractArxivIDFromURL(urlString) {
  if (!urlString) return undefined;
  const match = urlString.match(/(?:arxiv\.org\/(?:abs|pdf)\/)([a-z\-]+\/\d{7}(?:v\d+)?|\d{4}\.\d{4,5}(?:v\d+)?)/i);
  if (!match) return undefined;
  return match[1].replace(/\.pdf$/i, "");
}

async function directPDFMetadataForTab(tab) {
  const url = normalizeString(tab?.url);
  const wasObservedAsPDF = url ? await wasCapturedAsPDF(url, tab?.id) : false;
  if (!url || (!wasObservedAsPDF && !looksLikeDirectPDFURL(url))) {
    return undefined;
  }

  const title = normalizeString(tab?.title);
  return {
    title: title && title !== url ? title : undefined,
    doi: extractDOIFromURL(url),
    arxivId: extractArxivIDFromURL(url),
    pdfURL: url
  };
}

function hasCurrentPDF(metadata) {
  return Boolean(normalizeString(metadata?.pdfURL));
}

function sanitizeFilename(value) {
  const normalized = normalizeString(value) || "paper";
  return normalized
    .replace(/[<>:"/\\|?*\u0000-\u001f]/g, "_")
    .trim();
}

function storageArea() {
  return papyrusAPI.storage?.session ?? papyrusAPI.storage?.local;
}

async function loadStoredEntries(storageKey) {
  const area = storageArea();
  if (!area?.get) {
    return {};
  }

  const stored = await area.get(storageKey);
  return stored?.[storageKey] ?? {};
}

async function saveStoredEntries(storageKey, entries) {
  const area = storageArea();
  if (!area?.set) {
    return;
  }
  await area.set({ [storageKey]: entries });
}

async function loadCapturedPDFRequests() {
  return loadStoredEntries(CAPTURED_PDF_REQUESTS_STORAGE_KEY);
}

async function saveCapturedPDFRequests(entries) {
  await saveStoredEntries(CAPTURED_PDF_REQUESTS_STORAGE_KEY, entries);
}

async function loadCapturedPDFResponses() {
  return loadStoredEntries(CAPTURED_PDF_RESPONSES_STORAGE_KEY);
}

async function saveCapturedPDFResponses(entries) {
  await saveStoredEntries(CAPTURED_PDF_RESPONSES_STORAGE_KEY, entries);
}

function capturedPDFRequestKey(urlString, tabId) {
  return `${typeof tabId === "number" ? tabId : -1}|${normalizeURLForLookup(urlString)}`;
}

function pruneCapturedPDFRequests(entries) {
  const now = Date.now();
  const retained = Object.entries(entries)
    .filter(([, value]) => now - (value?.capturedAt ?? 0) <= CAPTURED_PDF_REQUEST_TTL_MS)
    .sort(([, left], [, right]) => (right?.capturedAt ?? 0) - (left?.capturedAt ?? 0))
    .slice(0, MAX_CAPTURED_PDF_REQUESTS);

  return Object.fromEntries(retained);
}

function pruneCapturedPDFResponses(entries) {
  const now = Date.now();
  const retained = Object.entries(entries)
    .filter(([, value]) => now - (value?.capturedAt ?? 0) <= CAPTURED_PDF_REQUEST_TTL_MS)
    .sort(([, left], [, right]) => (right?.capturedAt ?? 0) - (left?.capturedAt ?? 0))
    .slice(0, MAX_CAPTURED_PDF_REQUESTS);

  return Object.fromEntries(retained);
}

function sanitizedCapturedHeaders(rawHeaders) {
  if (!Array.isArray(rawHeaders)) {
    return undefined;
  }

  const allowed = {
    accept: "Accept",
    accept: "Accept",
    "accept-encoding": "Accept-Encoding",
    "accept-language": "Accept-Language",
    "cache-control": "Cache-Control",
    cookie: "Cookie",
    dnt: "DNT",
    pragma: "Pragma",
    priority: "Priority",
    referer: "Referer",
    "sec-ch-prefers-color-scheme": "Sec-CH-Prefers-Color-Scheme",
    "sec-ch-ua": "Sec-CH-UA",
    "sec-ch-ua-arch": "Sec-CH-UA-Arch",
    "sec-ch-ua-bitness": "Sec-CH-UA-Bitness",
    "sec-ch-ua-form-factors": "Sec-CH-UA-Form-Factors",
    "sec-ch-ua-full-version": "Sec-CH-UA-Full-Version",
    "sec-ch-ua-full-version-list": "Sec-CH-UA-Full-Version-List",
    "sec-ch-ua-mobile": "Sec-CH-UA-Mobile",
    "sec-ch-ua-model": "Sec-CH-UA-Model",
    "sec-ch-ua-platform": "Sec-CH-UA-Platform",
    "sec-ch-ua-platform-version": "Sec-CH-UA-Platform-Version",
    "sec-fetch-dest": "Sec-Fetch-Dest",
    "sec-fetch-mode": "Sec-Fetch-Mode",
    "sec-fetch-site": "Sec-Fetch-Site",
    "sec-fetch-user": "Sec-Fetch-User",
    "upgrade-insecure-requests": "Upgrade-Insecure-Requests",
    "user-agent": "User-Agent"
  };

  const headers = {};
  for (const header of rawHeaders) {
    const name = normalizeString(header?.name);
    const value = normalizeString(header?.value);
    if (!name || !value) {
      continue;
    }
    const lowercased = name.toLowerCase();
    const canonicalName = allowed[lowercased]
      || (lowercased.startsWith("sec-ch-ua-") ? name : undefined)
      || (lowercased.startsWith("sec-fetch-") ? name : undefined);
    if (!canonicalName) {
      continue;
    }
    headers[canonicalName] = value;
  }

  return Object.keys(headers).length > 0 ? headers : undefined;
}

async function recordCapturedPDFRequest(details) {
  if (!looksLikeDirectPDFURL(details?.url)) {
    return;
  }

  const headers = sanitizedCapturedHeaders(details.requestHeaders);
  if (!headers) {
    return;
  }

  const current = pruneCapturedPDFRequests(await loadCapturedPDFRequests());
  const normalizedURL = normalizeURLForLookup(details.url);
  const payload = {
    capturedAt: Date.now(),
    headers,
    url: normalizedURL
  };

  current[capturedPDFRequestKey(normalizedURL, details.tabId)] = payload;
  current[capturedPDFRequestKey(normalizedURL)] = payload;
  await saveCapturedPDFRequests(pruneCapturedPDFRequests(current));
}

async function capturedHeadersForPDFURL(urlString, tabId) {
  const current = pruneCapturedPDFRequests(await loadCapturedPDFRequests());
  const normalizedURL = normalizeURLForLookup(urlString);
  const exact = current[capturedPDFRequestKey(normalizedURL, tabId)];
  if (exact?.headers) {
    return exact.headers;
  }

  const generic = current[capturedPDFRequestKey(normalizedURL)];
  return generic?.headers;
}

function responseHeadersIndicatePDF(rawHeaders) {
  if (!Array.isArray(rawHeaders)) {
    return false;
  }

  let contentType;
  let contentDisposition;
  for (const header of rawHeaders) {
    const name = normalizeString(header?.name)?.toLowerCase();
    const value = normalizeString(header?.value);
    if (!name || !value) {
      continue;
    }
    if (name === "content-type") {
      contentType = value.toLowerCase();
    } else if (name === "content-disposition") {
      contentDisposition = value.toLowerCase();
    }
  }

  if (contentType?.includes("application/pdf")) {
    return true;
  }

  return Boolean(
    contentType?.includes("application/octet-stream")
    && contentDisposition?.includes(".pdf")
  );
}

async function recordCapturedPDFResponse(details) {
  const url = normalizeString(details?.url);
  if (!url || !responseHeadersIndicatePDF(details.responseHeaders)) {
    return;
  }

  const current = pruneCapturedPDFResponses(await loadCapturedPDFResponses());
  const normalizedURL = normalizeURLForLookup(url);
  const payload = {
    capturedAt: Date.now(),
    url: normalizedURL
  };

  current[capturedPDFRequestKey(normalizedURL, details.tabId)] = payload;
  current[capturedPDFRequestKey(normalizedURL)] = payload;
  await saveCapturedPDFResponses(pruneCapturedPDFResponses(current));
}

async function wasCapturedAsPDF(urlString, tabId) {
  const current = pruneCapturedPDFResponses(await loadCapturedPDFResponses());
  const normalizedURL = normalizeURLForLookup(urlString);
  const exact = current[capturedPDFRequestKey(normalizedURL, tabId)];
  if (exact) {
    return true;
  }

  return Boolean(current[capturedPDFRequestKey(normalizedURL)]);
}

async function capturedReferrerForPDFURL(urlString, tabId) {
  const headers = await capturedHeadersForPDFURL(urlString, tabId);
  const referrer = normalizeString(headers?.Referer);
  if (!referrer || looksLikeDirectPDFURL(referrer)) {
    return undefined;
  }
  return referrer;
}

function suggestedPDFFilename(metadata) {
  if (metadata?.title) {
    return `${sanitizeFilename(metadata.title)}.pdf`;
  }
  try {
    const pathname = new URL(metadata?.pdfURL || "").pathname;
    const lastPath = decodeURIComponent(pathname.split("/").filter(Boolean).pop() || "paper.pdf");
    const filename = sanitizeFilename(lastPath);
    return /\.pdf$/i.test(filename) ? filename : `${filename}.pdf`;
  } catch {
    return "paper.pdf";
  }
}

function arrayBufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  const chunkSize = 0x8000;
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    const chunk = bytes.subarray(offset, offset + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}

async function fetchPDFBase64(pdfURL) {
  const response = await fetch(pdfURL, {
    credentials: "include"
  });
  if (!response.ok) {
    throw new Error(`Failed to fetch the current PDF (${response.status}).`);
  }

  const buffer = await response.arrayBuffer();
  const bytes = new Uint8Array(buffer);
  const isPDF = bytes.length >= 4
    && bytes[0] === 0x25
    && bytes[1] === 0x50
    && bytes[2] === 0x44
    && bytes[3] === 0x46;
  if (!isPDF) {
    throw new Error("Safari did not return PDF bytes for the current tab.");
  }

  return arrayBufferToBase64(buffer);
}

async function fetchPDFBase64FromPage(tab, pdfURL) {
  if (!tab?.id) {
    throw new Error("No active tab available for in-page PDF fetch.");
  }

  await papyrusAPI.scripting.executeScript({
    target: { tabId: tab.id },
    files: ["src/content.js"]
  });

  const response = await papyrusAPI.tabs.sendMessage(tab.id, {
    type: MESSAGE_FETCH_CURRENT_PDF,
    url: pdfURL
  });

  if (!response?.ok || !response.pdfBase64) {
    throw new Error(response?.error || "Failed to fetch the current PDF from page context.");
  }

  return response.pdfBase64;
}

async function cookieHeaderForURL(urlString) {
  const cookiesAPI = papyrusAPI.cookies;
  if (!cookiesAPI?.getAll) {
    return undefined;
  }

  try {
    const cookies = await cookiesAPI.getAll({ url: urlString });
    if (!Array.isArray(cookies) || cookies.length === 0) {
      return undefined;
    }
    return cookies
      .filter((cookie) => normalizeString(cookie?.name) && typeof cookie?.value === "string")
      .map((cookie) => `${cookie.name}=${cookie.value}`)
      .join("; ");
  } catch {
    return undefined;
  }
}

function normalizeImportMetadata(raw) {
  const metadata = raw && typeof raw === "object" ? raw : {};
  return {
    title: normalizeString(metadata.title),
    doi: normalizeString(metadata.doi),
    arxivId: normalizeString(metadata.arxivId),
    pdfURL: normalizeString(metadata.pdfURL),
    sourceURL: normalizeString(metadata.sourceURL)
  };
}

async function withBrowserContext(rawMetadata, tab) {
  const metadata = normalizeImportMetadata(rawMetadata);
  if (!metadata.pdfURL) {
    return metadata;
  }

  if (!metadata.sourceURL) {
    metadata.sourceURL = await capturedReferrerForPDFURL(metadata.pdfURL, tab?.id);
  }

  const tabTitle = normalizeString(tab?.title);
  if (!metadata.title && tabTitle && tabTitle !== metadata.pdfURL) {
    metadata.title = tabTitle;
  }

  return metadata;
}

function isSafariWebExtension() {
  try {
    const extensionURL = papyrusAPI.runtime?.getURL?.("") ?? "";
    return extensionURL.startsWith("safari-web-extension://");
  } catch {
    return false;
  }
}

async function sendSafariNativeMessage(message) {
  const sendNativeMessage = papyrusAPI.runtime?.sendNativeMessage;
  if (typeof sendNativeMessage !== "function") {
    throw new Error("Safari native messaging is unavailable.");
  }

  let lastError;
  for (const args of [[message], ["", message]]) {
    try {
      return await sendNativeMessage.apply(papyrusAPI.runtime, args);
    } catch (error) {
      lastError = error;
    }
  }

  throw lastError instanceof Error ? lastError : new Error("Safari native messaging failed.");
}

async function wakeUpPapyrus(tab) {
  if (isSafariWebExtension()) {
    await sendSafariNativeMessage({ type: NATIVE_MESSAGE_OPEN_PAPYRUS });
    return;
  }

  // Chrome: inject anchor click into current tab to open papyrus://open
  if (tab?.id) {
    try {
      await papyrusAPI.scripting.executeScript({
        target: { tabId: tab.id },
        func: (url) => {
          const a = document.createElement("a");
          a.href = url;
          a.style.display = "none";
          document.body.appendChild(a);
          a.click();
          setTimeout(() => a.remove(), 100);
        },
        args: ["papyrus://open"]
      });
      return;
    } catch {
      // Tab not scriptable, fall through
    }
  }

  const newTab = await papyrusAPI.tabs.create({ url: "papyrus://open", active: false });
  setTimeout(() => papyrusAPI.tabs.remove(newTab.id).catch(() => {}), 2000);
}

async function postImportToPapyrus(payload) {
  const response = await fetch(`http://127.0.0.1:${PAPYRUS_HTTP_PORT}/import`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(30_000)
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error || `Papyrus returned HTTP ${response.status}.`);
  }
  return response.json();
}

async function triggerAppImport(rawMetadata, tab) {
  const metadata = await withBrowserContext(rawMetadata, tab);
  if (!hasCurrentPDF(metadata)) {
    throw new Error("Open the PDF page itself before saving.");
  }

  // Fetch PDF bytes in browser context (preserves session cookies)
  const pdfBase64 = await fetchPDFBase64FromPage(tab, metadata.pdfURL)
    .catch(() => fetchPDFBase64(metadata.pdfURL));

  const payload = {
    pdfBase64,
    filename: suggestedPDFFilename(metadata),
    metadata
  };

  // Try direct HTTP POST to Papyrus
  try {
    return await postImportToPapyrus(payload);
  } catch {
    // Papyrus not running — wake it up, then retry
  }

  await wakeUpPapyrus(tab);

  let lastError;
  for (let i = 0; i < 8; i++) {
    await new Promise((resolve) => setTimeout(resolve, 750));
    try {
      return await postImportToPapyrus(payload);
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError ?? new Error("Papyrus did not start in time.");
}

async function extractFromActiveTab(tab) {
  if (!tab?.id) {
    throw new Error("No active tab available.");
  }
  const fallbackPDFMetadata = await directPDFMetadataForTab(tab);
  if (fallbackPDFMetadata) {
    return fallbackPDFMetadata;
  }
  await papyrusAPI.scripting.executeScript({
    target: { tabId: tab.id },
    files: INJECTABLE_FILES
  });

  const response = await papyrusAPI.tabs.sendMessage(tab.id, {
    type: MESSAGE_EXTRACT
  });
  if (!response?.ok) {
    throw new Error(response?.error || "Failed to extract metadata from current page.");
  }
  if (response.pageType !== "pdf" || !hasCurrentPDF(response.metadata)) {
    throw new Error("Open the PDF page itself before saving.");
  }
  return response.metadata;
}

async function ensureToastScriptInjected(tabId) {
  if (!tabId) {
    return;
  }
  await papyrusAPI.scripting.executeScript({
    target: { tabId },
    files: TOAST_INJECTABLE_FILES
  });
}

async function showToastOnTab(tabId, kind) {
  if (!tabId) {
    return;
  }
  try {
    await ensureToastScriptInjected(tabId);
    await papyrusAPI.tabs.sendMessage(tabId, {
      type: MESSAGE_SHOW_TOAST,
      kind
    });
  } catch (error) {
    console.warn("[Papyrus] browser toast failed:", error);
  }
}

function toastKindForErrorMessage(message) {
  return message === "Open the PDF page itself before saving."
    ? "cannot-save"
    : "failure";
}

async function saveActiveTabToPapyrus(tab) {
  try {
    await showToastOnTab(tab?.id, "saving");
    const metadata = await extractFromActiveTab(tab);
    await triggerAppImport(metadata, tab);
    await showToastOnTab(tab?.id, "success");
  } catch (error) {
    const message = error instanceof Error ? error.message : "Save to Papyrus failed.";
    await showToastOnTab(tab?.id, toastKindForErrorMessage(message));
    console.warn("[Papyrus] active-tab import failed:", message);
  }
}

papyrusAPI.action.onClicked.addListener((tab) => {
  void saveActiveTabToPapyrus(tab);
});

function registerCapturedPDFRequestListener() {
  const onBeforeSendHeaders = papyrusAPI.webRequest?.onBeforeSendHeaders;
  if (!onBeforeSendHeaders?.addListener) {
    return;
  }

  const listener = (details) => {
    void recordCapturedPDFRequest(details);
  };

  const filter = {
    urls: ["*://*/*"],
    types: ["main_frame", "sub_frame", "object", "other"]
  };

  try {
    onBeforeSendHeaders.addListener(listener, filter, ["requestHeaders", "extraHeaders"]);
  } catch {
    try {
      onBeforeSendHeaders.addListener(listener, filter, ["requestHeaders"]);
    } catch {
      // Ignore unsupported webRequest capabilities in non-Safari browsers.
    }
  }
}

function registerCapturedPDFResponseListener() {
  const onHeadersReceived = papyrusAPI.webRequest?.onHeadersReceived;
  if (!onHeadersReceived?.addListener) {
    return;
  }

  const listener = (details) => {
    void recordCapturedPDFResponse(details);
  };

  const filter = {
    urls: ["*://*/*"],
    types: ["main_frame", "sub_frame", "object", "other"]
  };

  try {
    onHeadersReceived.addListener(listener, filter, ["responseHeaders", "extraHeaders"]);
  } catch {
    try {
      onHeadersReceived.addListener(listener, filter, ["responseHeaders"]);
    } catch {
      // Ignore unsupported webRequest capabilities in non-Safari browsers.
    }
  }
}

registerCapturedPDFRequestListener();
registerCapturedPDFResponseListener();
