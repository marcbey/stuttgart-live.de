import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video", "button", "playbackButton"]

  static values = { media: { type: String, default: "(min-width: 0px)" } }

  connect() {
    this.sync = this.sync.bind(this)
    this.updatePlayback = this.updatePlayback.bind(this)
    this.unloadVideo = this.unloadVideo.bind(this)
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
    } else if (!this.userPaused) {
      this.playVideo()
    }
    this.sync()
  }

  unloadVideo() {
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
      this.updatePlayback()
    }
    this.sync()
  }

  playVideo() {
    const source = this.videoTarget.dataset.videoSoundSrcValue
    if (source && !this.videoTarget.hasAttribute("src")) this.videoTarget.src = source
    this.videoTarget.volume = this.videoTarget.volume || 1

    const playback = this.videoTarget.play()
    if (playback?.catch) {
      playback.catch(() => {
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
