const offerButtons = document.querySelectorAll(".offer-select");
const bookingChoices = document.querySelectorAll(".booking-choice");
const packageSelect = document.querySelector("#paket-select");
const requestForm = document.querySelector("#request-form");
const scrollTopButton = document.querySelector(".scroll-top");
const mobileGalleryQuery = window.matchMedia("(max-width: 47.99rem)");
const reduceMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
const galleryTimers = new Map();

function setBookingChoiceOpen(choice, isOpen) {
  const trigger = choice.querySelector(".booking-trigger");

  choice.classList.toggle("is-open", isOpen);
  trigger?.setAttribute("aria-expanded", String(isOpen));
}

function closeBookingChoices(exceptChoice = null) {
  bookingChoices.forEach((choice) => {
    if (choice !== exceptChoice) {
      setBookingChoiceOpen(choice, false);
    }
  });
}

bookingChoices.forEach((choice) => {
  const trigger = choice.querySelector(".booking-trigger");

  choice.addEventListener("mouseenter", () => {
    closeBookingChoices(choice);
    setBookingChoiceOpen(choice, true);
  });

  choice.addEventListener("mouseleave", () => {
    if (!choice.contains(document.activeElement)) {
      setBookingChoiceOpen(choice, false);
    }
  });

  choice.addEventListener("focusin", () => {
    closeBookingChoices(choice);
    setBookingChoiceOpen(choice, true);
  });

  trigger?.addEventListener("click", (event) => {
    event.preventDefault();

    if (window.matchMedia("(hover: hover)").matches && choice.matches(":hover")) {
      closeBookingChoices(choice);
      setBookingChoiceOpen(choice, true);
      return;
    }

    const shouldOpen = !choice.classList.contains("is-open");
    closeBookingChoices(choice);
    setBookingChoiceOpen(choice, shouldOpen);
  });

  choice.addEventListener("focusout", (event) => {
    if (!choice.contains(event.relatedTarget)) {
      setBookingChoiceOpen(choice, false);
    }
  });
});

document.addEventListener("click", (event) => {
  if (!event.target.closest(".booking-choice")) {
    closeBookingChoices();
  }
});

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") {
    return;
  }

  const openChoice = document.querySelector(".booking-choice.is-open");
  closeBookingChoices();
  openChoice?.querySelector(".booking-trigger")?.focus();
});

offerButtons.forEach((button) => {
  button.addEventListener("click", () => {
    if (packageSelect) {
      packageSelect.value = button.dataset.package;
    }

    document.querySelector("#anfrage")?.scrollIntoView({ behavior: "smooth", block: "start" });
  });
});

requestForm?.addEventListener("submit", (event) => {
  event.preventDefault();

  const data = new FormData(requestForm);
  const subject = `MAMMA MIA! Anfrage: ${data.get("paket") || "Premium-Erlebnis"}`;
  const body = [
    "Sehr geehrter Herr Woog,",
    "",
    "ich interessiere mich fuer ein MAMMA MIA! Premium-Erlebnis.",
    "",
    `Name: ${data.get("name") || ""}`,
    `Firma oder Anlass: ${data.get("anlass") || ""}`,
    `E-Mail: ${data.get("email") || ""}`,
    `Telefon: ${data.get("telefon") || ""}`,
    `Personenanzahl: ${data.get("personen") || ""}`,
    `Gewuenschtes Paket: ${data.get("paket") || ""}`,
    `Bevorzugtes Datum: ${data.get("datum") || ""}`,
    `Zielgruppe: ${data.get("zielgruppe") || ""}`,
    "",
    "Weitere Infos:",
    `${data.get("nachricht") || ""}`,
    "",
    "Viele Gruesse"
  ].join("\n");

  const mailto = `mailto:paulwoog@russ-live.de?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  window.location.href = mailto;
});

function updateScrollTopButton() {
  if (!scrollTopButton) {
    return;
  }

  scrollTopButton.classList.toggle("is-visible", window.scrollY > 520);
}

scrollTopButton?.addEventListener("click", () => {
  window.scrollTo({ top: 0, behavior: "smooth" });
});

window.addEventListener("scroll", updateScrollTopButton, { passive: true });
updateScrollTopButton();

function setActiveGalleryCard(gallery, nextIndex) {
  const cards = [...gallery.querySelectorAll(".gallery-card")];

  cards.forEach((card, index) => {
    card.classList.toggle("is-active", index === nextIndex);
  });
}

function clearGalleryTimer(gallery) {
  const timer = galleryTimers.get(gallery);

  if (timer) {
    window.clearInterval(timer);
    galleryTimers.delete(gallery);
  }
}

function setupMobileGallery(gallery) {
  const cards = [...gallery.querySelectorAll(".gallery-card")];

  clearGalleryTimer(gallery);

  if (!mobileGalleryQuery.matches || cards.length < 2) {
    setActiveGalleryCard(gallery, 0);
    return;
  }

  let currentIndex = 0;
  setActiveGalleryCard(gallery, currentIndex);

  if (reduceMotionQuery.matches) {
    return;
  }

  const timer = window.setInterval(() => {
    currentIndex = (currentIndex + 1) % cards.length;
    setActiveGalleryCard(gallery, currentIndex);
  }, 4200);

  galleryTimers.set(gallery, timer);
}

function syncMobileGalleries() {
  document.querySelectorAll(".theme-gallery, .catering-gallery").forEach((gallery) => {
    setupMobileGallery(gallery);
  });
}

mobileGalleryQuery.addEventListener("change", syncMobileGalleries);
reduceMotionQuery.addEventListener("change", syncMobileGalleries);
syncMobileGalleries();
