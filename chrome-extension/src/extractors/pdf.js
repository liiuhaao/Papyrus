(function pdfExtractorBootstrap() {
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

  function looksLikePDFURL(urlString = location.href) {
    return /\.pdf(?:$|[?#])/i.test(urlString)
      || /openreview\.net\/pdf\?id=/i.test(urlString)
      || /arxiv\.org\/pdf\//i.test(urlString)
      || /\/doi\/(?:pdf|epdf)\//i.test(urlString);
  }

  function hasEmbeddedPDFNode() {
    if (document.contentType?.toLowerCase() === "application/pdf") {
      return true;
    }
    if (document.querySelector('embed[type="application/pdf"], object[type="application/pdf"]')) {
      return true;
    }
    if (document.querySelector("iframe[src*='.pdf'], embed[src*='.pdf'], object[data*='.pdf']")) {
      return true;
    }
    return false;
  }

  function hasChromePDFViewerSignature() {
    return Boolean(
      document.querySelector("pdf-viewer, viewer-pdf-toolbar")
      || document.querySelector('iframe[src*="chrome-extension://"][src*="pdf"]')
    );
  }

  function isPDFPage() {
    return looksLikePDFURL(location.href) || hasEmbeddedPDFNode() || hasChromePDFViewerSignature();
  }

  function extract() {
    if (!isPDFPage()) {
      return {};
    }

    const title = document.title?.trim() || undefined;
    const referrerURL = (() => {
      const raw = document.referrer?.trim();
      if (!raw || raw === location.href) {
        return undefined;
      }
      return raw;
    })();

    return {
      title,
      doi: extractDOIFromURL(location.href),
      arxivId: extractArxivIDFromURL(location.href),
      pdfURL: location.href,
      sourceURL: referrerURL
    };
  }

  globalThis.PapyrusExtractors = globalThis.PapyrusExtractors || {};
  globalThis.PapyrusExtractors.pdf = {
    isPDFPage,
    extract
  };
})();
