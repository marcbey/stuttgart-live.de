// Use the referring page rather than history.back(): section links create
// history entries inside the landing page, and links can open in a new tab.
(() => {
  const backLink = document.querySelector("[data-landing-back]");
  if (!backLink || !document.referrer) return;

  try {
    const source = new URL(document.referrer);
    const current = new URL(window.location.href);
    const samePage = source.origin === current.origin &&
      source.pathname.replace(/\/$/, "") === current.pathname.replace(/\/$/, "");

    if (["http:", "https:"].includes(source.protocol) && !samePage) {
      backLink.href = source.href;
    }
  } catch {
    // Keep the homepage fallback if no usable referring page is available.
  }
})();
