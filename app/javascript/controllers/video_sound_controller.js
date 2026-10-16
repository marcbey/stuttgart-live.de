import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video", "button", "playbackButton"]

  connect() {
    this.sync = this.sync.bind(this)
    this.handleMotionChange = this.handleMotionChange.bind(this)
    this.reduceMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.userPaused = this.userPaused || false
    this.reduceMotionQuery.addEventListener("change", this.handleMotionChange)

    if (this.hasVideoTarget) {
      this.videoTarget.autoplay = false
      for (const event of ["volumechange", "loadedmetadata", "play", "pause", "ended"]) {
        this.videoTarget.addEventListener(event, this.sync)
      }
      this.handleMotionChange()
    }

    this.sync()
  }

  disconnect() {
    this.reduceMotionQuery?.removeEventListener("change", this.handleMotionChange)
    if (!this.hasVideoTarget) return

    for (const event of ["volumechange", "loadedmetadata", "play", "pause", "ended"]) {
      this.videoTarget.removeEventListener(event, this.sync)
    }
    this.videoTarget.pause()
  }

  handleMotionChange() {
    if (!this.hasVideoTarget) return

    if (this.reduceMotionQuery.matches) {
      this.videoTarget.pause()
      this.videoTarget.load()
    } else if (!this.userPaused) {
      this.playVideo()
    }
    this.sync()
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
    if (this.userPaused) {
      this.videoTarget.pause()
    } else {
      this.playVideo()
    }
    this.sync()
  }

  playVideo() {
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
      const unmuted = !this.videoTarget.muted
      this.buttonTarget.classList.toggle("is-unmuted", unmuted)
      this.buttonTarget.setAttribute("aria-pressed", unmuted.toString())
      this.buttonTarget.setAttribute("aria-label", unmuted ? "Ton ausschalten" : "Ton einschalten")
    }

    if (this.hasPlaybackButtonTarget) {
      const paused = this.videoTarget.paused
      this.playbackButtonTarget.classList.toggle("is-paused", paused)
      this.playbackButtonTarget.setAttribute("aria-pressed", paused.toString())
      this.playbackButtonTarget.setAttribute("aria-label", paused ? "Video abspielen" : "Video pausieren")
    }
  }
}
