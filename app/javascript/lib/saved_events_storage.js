export const STORAGE_KEY = "stuttgart-live:saved-events"

function storage() {
  if (typeof window === "undefined") return null

  try {
    return window.localStorage
  } catch (_error) {
    return null
  }
}

function normalizeEntry(entry) {
  if (typeof entry === "string") {
    const slug = entry.trim()
    return slug.length > 0 ? { slug } : null
  }

  if (entry && typeof entry === "object") {
    const slug = entry.slug?.toString().trim()
    return slug ? { slug } : null
  }

  return null
}

export function readSavedEvents() {
  const adapter = storage()
  if (!adapter) return []

  const raw = adapter.getItem(STORAGE_KEY)
  if (!raw) return []

  try {
    const parsed = JSON.parse(raw)
    if (!Array.isArray(parsed)) {
      adapter.removeItem(STORAGE_KEY)
      return []
    }

    const seen = new Set()
    return parsed.map(normalizeEntry).filter((entry) => {
      if (!entry || seen.has(entry.slug)) return false

      seen.add(entry.slug)
      return true
    })
  } catch (_error) {
    adapter.removeItem(STORAGE_KEY)
    return []
  }
}

export function writeSavedEvents(events) {
  const adapter = storage()
  if (!adapter) return

  const normalizedEvents = Array.isArray(events) ? events.map(normalizeEntry).filter(Boolean) : []
  adapter.setItem(STORAGE_KEY, JSON.stringify(normalizedEvents))
}

export function savedEventSlugs() {
  return readSavedEvents().map((entry) => entry.slug)
}

export function isSavedEvent(slug) {
  return savedEventSlugs().includes(slug)
}

export function addSavedEvent(slug) {
  const normalizedSlug = slug?.toString().trim()
  if (!normalizedSlug) return false
  if (isSavedEvent(normalizedSlug)) return false

  const events = readSavedEvents()
  events.push({ slug: normalizedSlug })
  writeSavedEvents(events)
  return true
}

export function removeSavedEvent(slug) {
  const normalizedSlug = slug?.toString().trim()
  if (!normalizedSlug) return false

  const events = readSavedEvents()
  const filteredEvents = events.filter((entry) => entry.slug !== normalizedSlug)
  if (filteredEvents.length === events.length) return false

  writeSavedEvents(filteredEvents)
  return true
}
