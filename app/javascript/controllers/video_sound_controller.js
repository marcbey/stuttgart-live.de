import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video", "button", "playbackButton", "link", "copy", "title", "subtitle", "date", "location", "adminLink"]

  static values = {
    media: { type: String, default: "(min-width: 0px)" },
    playlist: { type: Array, default: [] },
    storageKey: { type: String, default: "" }
  }

  connect() {
    this.sync = this.sync.bind(this)
    this.updatePlayback = this.updatePlayback.bind(this)
    this.unloadVideo = this.unloadVideo.bind(this)
    this.advancePlaylist = this.advancePlaylist.bind(this)
    const sources = new Set()
    this.playlist = this.playlistValue.filter(entry => {
      if (!entry?.src || sources.has(entry.src)) return false
      sources.add(entry.src)
      return true
    })
    this.currentEntry = null
    this.playlistEnded = false
    this.needsNextClip = false
    this.playlistState = null
    this.playbackAttempt = 0
    this.reduceMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.mediaQuery = window.matchMedia(this.mediaValue)
    this.userPaused = this.userPaused || false
    this.explicitPlayback = false
    this.visible = false
    this.reduceMotionQuery.addEventListener("change", this.updatePlayback)
    this.mediaQuery.addEventListener("change", this.updatePlayback)
    navigator.connection?.addEventListener("change", this.updatePlayback)
    document.addEventListener("visibilitychange", this.updatePlayback)
    document.addEventListener("turbo:before-cache", this.unloadVideo)

    if (this.hasVideoTarget) {
      this.videoTarget.autoplay = false
      if (this.playlist.length) this.videoTarget.loop = false
      this.videoTarget.addEventListener("ended", this.advancePlaylist)
      for (const event of ["volumechange", "loadedmetadata", "play", "pause", "ended"]) {
        this.videoTarget.addEventListener(event, this.sync)
      }
      this.visibilityObserver = new IntersectionObserver(([entry]) => {
        this.visible = entry.isIntersecting && entry.intersectionRect.width > 0 && entry.intersectionRect.height > 0
        this.updatePlayback()
      })
      this.visibilityObserver.observe(this.videoTarget)
    }

    this.sync()
  }

  disconnect() {
    this.visibilityObserver?.disconnect()
    this.reduceMotionQuery?.removeEventListener("change", this.updatePlayback)
    this.mediaQuery?.removeEventListener("change", this.updatePlayback)
    navigator.connection?.removeEventListener("change", this.updatePlayback)
    document.removeEventListener("visibilitychange", this.updatePlayback)
    document.removeEventListener("turbo:before-cache", this.unloadVideo)
    if (!this.hasVideoTarget) return

    this.videoTarget.removeEventListener("ended", this.advancePlaylist)
    for (const event of ["volumechange", "loadedmetadata", "play", "pause", "ended"]) {
      this.videoTarget.removeEventListener(event, this.sync)
    }
    this.unloadVideo()
  }

  updatePlayback() {
    if (!this.hasVideoTarget) return

    const eligible = this.mediaQuery.matches && this.visible && !document.hidden
    const automaticPlayback = !this.reduceMotionQuery.matches && !navigator.connection?.saveData
    if (!eligible || (!automaticPlayback && !this.explicitPlayback)) {
      this.unloadVideo()
    } else if (!this.userPaused && !this.playlistEnded) {
      if (this.playlist.length && (!this.currentEntry || this.needsNextClip)) this.selectNextClip()
      this.playVideo()
    }
    this.sync()
  }

  unloadVideo() {
    if (!this.hasVideoTarget) return
    this.playbackAttempt++
    this.videoTarget.pause()
    if (this.videoTarget.dataset.videoSoundSrcValue && this.videoTarget.hasAttribute("src")) {
      this.videoTarget.removeAttribute("src")
      this.videoTarget.load()
    }
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    if (!this.hasVideoTarget) return

    this.videoTarget.muted = !this.videoTarget.muted
    this.sync()
  }

  togglePlayback(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasVideoTarget) return

    this.userPaused = !this.videoTarget.paused
    this.explicitPlayback = !this.userPaused
    if (this.userPaused) {
      this.videoTarget.pause()
    } else {
      this.playlistEnded = false
      this.updatePlayback()
    }
    this.sync()
  }

  advancePlaylist() {
    if (!this.playlist.length) return

    this.playlistEnded = this.playlist.length === 1
    this.needsNextClip = !this.playlistEnded
    this.updatePlayback()
  }

  selectNextClip() {
    const sources = this.playlist.map(entry => entry.src)
    const signature = JSON.stringify([...sources].sort())
    if (!this.playlistState) {
      try {
        this.playlistState = this.storageKeyValue ? JSON.parse(window.sessionStorage.getItem(this.storageKeyValue)) : null
      } catch {
        // Storage can be unavailable in private browsing or contain outdated data.
      }
      const state = this.playlistState
      if (state?.signature !== signature || !Array.isArray(state.remaining) ||
          state.remaining.some(src => !sources.includes(src)) || new Set(state.remaining).size !== state.remaining.length ||
          (state.last !== null && !sources.includes(state.last)) || state.remaining.includes(state.last)) {
        this.playlistState = { signature, remaining: [...sources], last: null }
      }
    }

    const state = this.playlistState
    if (!state.remaining.length) state.remaining = [...sources]
    const candidates = state.remaining.filter(src => sources.length === 1 || src !== state.last)
    const source = candidates[Math.floor(Math.random() * candidates.length)]
    state.remaining = state.remaining.filter(src => src !== source)
    state.last = source
    try {
      if (this.storageKeyValue) window.sessionStorage.setItem(this.storageKeyValue, JSON.stringify(state))
    } catch {
      // The in-memory round still works without session storage.
    }

    this.unloadVideo()
    this.currentEntry = this.playlist.find(entry => entry.src === source)
    this.needsNextClip = false
    this.videoTarget.dataset.videoSoundSrcValue = source
    this.updateClipDetails(this.currentEntry)
  }

  updateClipDetails(entry) {
    if (entry.poster) this.videoTarget.setAttribute("poster", entry.poster)
    else this.videoTarget.removeAttribute("poster")
    this.element.dataset.videoOrientation = entry.orientation || "landscape"

    for (const name of ["title", "subtitle", "date", "location"]) {
      if (!this[`has${name[0].toUpperCase()}${name.slice(1)}Target`]) continue
      this[`${name}Target`].textContent = entry[name] || ""
      this[`${name}Target`].hidden = !entry[name]
    }
    if (this.hasCopyTarget) this.copyTarget.hidden = !entry.overlay || ![entry.title, entry.subtitle, entry.date, entry.location].some(Boolean)
    if (this.hasLinkTarget) {
      if (entry.href) this.linkTarget.setAttribute("href", entry.href)
      else this.linkTarget.removeAttribute("href")
      if (entry.label) this.linkTarget.setAttribute("aria-label", entry.label)
      else this.linkTarget.removeAttribute("aria-label")
    }
    if (this.hasAdminLinkTarget) {
      this.adminLinkTarget.hidden = !entry.adminHref
      if (entry.adminHref) this.adminLinkTarget.setAttribute("href", entry.adminHref)
      else this.adminLinkTarget.removeAttribute("href")
    }
  }

  playVideo() {
    const attempt = ++this.playbackAttempt
    const source = this.videoTarget.dataset.videoSoundSrcValue
    if (source && !this.videoTarget.hasAttribute("src")) this.videoTarget.src = source
    this.videoTarget.volume = this.videoTarget.volume || 1

    const playback = this.videoTarget.play()
    if (playback?.catch) {
      playback.catch(() => {
        if (attempt !== this.playbackAttempt) return
        this.videoTarget.muted = true
        this.sync()
      })
    }
  }

  sync() {
    if (!this.hasVideoTarget) return

    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = !this.mediaQuery.matches
      const unmuted = !this.videoTarget.muted
      this.buttonTarget.classList.toggle("is-unmuted", unmuted)
      this.buttonTarget.setAttribute("aria-pressed", unmuted.toString())
      this.buttonTarget.setAttribute("aria-label", unmuted ? "Ton ausschalten" : "Ton einschalten")
    }

    if (this.hasPlaybackButtonTarget) {
      this.playbackButtonTarget.disabled = !this.mediaQuery.matches
      const paused = this.videoTarget.paused
      this.playbackButtonTarget.classList.toggle("is-paused", paused)
      this.playbackButtonTarget.setAttribute("aria-pressed", paused.toString())
      this.playbackButtonTarget.setAttribute("aria-label", paused ? "Video abspielen" : "Video pausieren")
    }
  }
}
