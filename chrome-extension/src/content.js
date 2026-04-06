(function contentBootstrap() {
  if (globalThis.__papyrusContentInitialized) {
    return;
  }
  globalThis.__papyrusContentInitialized = true;

  const papyrusAPI = globalThis.browser ?? globalThis.chrome;
  const MESSAGE_EXTRACT = "PAPYRUS_EXTRACT";
  const MESSAGE_FETCH_CURRENT_PDF = "PAPYRUS_FETCH_CURRENT_PDF";
  const MESSAGE_SHOW_TOAST = "PAPYRUS_SHOW_TOAST";
  const TOAST_CONTAINER_ID = "papyrus-extension-toast-root";

  function hasCurrentPDF(metadata) {
    return Boolean(metadata?.pdfURL);
  }

  function ensureToastContainer() {
    let root = document.getElementById(TOAST_CONTAINER_ID);
    if (root) {
      return root;
    }

    root = document.createElement("div");
    root.id = TOAST_CONTAINER_ID;
    root.style.position = "fixed";
    root.style.top = "20px";
    root.style.right = "20px";
    root.style.zIndex = "2147483647";
    root.style.display = "flex";
    root.style.flexDirection = "column";
    root.style.gap = "10px";
    root.style.pointerEvents = "none";
    document.documentElement.appendChild(root);
    return root;
  }

  function toastConfig(kind) {
    switch (kind) {
      case "saving":
        return {
          message: "Saving to Papyrus...",
          background: "#1f2937",
          border: "#334155",
          color: "#f8fafc"
        };
      case "success":
        return {
          message: "Saved to Papyrus",
          background: "#14532d",
          border: "#166534",
          color: "#f0fdf4"
        };
      case "cannot-save":
        return {
          message: "Cannot save. Open the PDF page first.",
          background: "#78350f",
          border: "#92400e",
          color: "#fffbeb"
        };
      case "failure":
      default:
        return {
          message: "Save to Papyrus failed",
          background: "#7f1d1d",
          border: "#991b1b",
          color: "#fef2f2"
        };
    }
  }

  function showToast(kind) {
    const root = ensureToastContainer();
    const config = toastConfig(kind);

    const toast = document.createElement("div");
    toast.textContent = config.message;
    toast.style.maxWidth = "320px";
    toast.style.padding = "11px 14px";
    toast.style.borderRadius = "12px";
    toast.style.border = `1px solid ${config.border}`;
    toast.style.background = config.background;
    toast.style.color = config.color;
    toast.style.font = '600 13px/1.35 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif';
    toast.style.boxShadow = "0 14px 30px rgba(15, 23, 42, 0.28)";
    toast.style.opacity = "0";
    toast.style.transform = "translateY(-8px)";
    toast.style.transition = "opacity 160ms ease, transform 160ms ease";

    root.appendChild(toast);
    requestAnimationFrame(() => {
      toast.style.opacity = "1";
      toast.style.transform = "translateY(0)";
    });

    const remove = () => {
      toast.style.opacity = "0";
      toast.style.transform = "translateY(-8px)";
      setTimeout(() => toast.remove(), 180);
    };

    setTimeout(remove, kind === "saving" ? 1400 : 2200);
  }

  function detectPageType() {
    const extractors = globalThis.PapyrusExtractors || {};
    if (extractors.pdf?.isPDFPage?.()) {
      return "pdf";
    }
    return "page";
  }

  function extractCurrentPageMetadata() {
    const extractors = globalThis.PapyrusExtractors || {};
    const pageType = detectPageType();

    const metadata = pageType === "pdf"
      ? (extractors.pdf?.extract?.() || {})
      : {};
    return { metadata, pageType };
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

  async function fetchCurrentPDF(url) {
    const targetURL = typeof url === "string" && url.trim() ? url : globalThis.location?.href;
    const response = await fetch(targetURL, {
      credentials: "include"
    });
    if (!response.ok) {
      return {
        ok: false,
        error: `Failed to fetch the current PDF (${response.status}).`
      };
    }

    const buffer = await response.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    const isPDF = bytes.length >= 4
      && bytes[0] === 0x25
      && bytes[1] === 0x50
      && bytes[2] === 0x44
      && bytes[3] === 0x46;
    if (!isPDF) {
      return {
        ok: false,
        error: "Current page response was not a PDF."
      };
    }

    return {
      ok: true,
      pdfBase64: arrayBufferToBase64(buffer)
    };
  }

  papyrusAPI.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type === MESSAGE_EXTRACT) {
      try {
        const payload = extractCurrentPageMetadata();
        sendResponse({ ok: true, ...payload });
      } catch (error) {
        sendResponse({
          ok: false,
          error: error instanceof Error ? error.message : "Failed to extract page metadata."
        });
      }
      return false;
    }

    if (message?.type === MESSAGE_FETCH_CURRENT_PDF) {
      fetchCurrentPDF(message.url)
        .then((result) => sendResponse(result))
        .catch((error) => {
          sendResponse({
            ok: false,
            error: error instanceof Error ? error.message : "Failed to fetch current PDF from page context."
          });
        });
      return true;
    }

    if (message?.type === MESSAGE_SHOW_TOAST) {
      try {
        showToast(message.kind);
        sendResponse({ ok: true });
      } catch (error) {
        sendResponse({
          ok: false,
          error: error instanceof Error ? error.message : "Failed to show browser toast."
        });
      }
      return false;
    }

    return false;
  });
})();
