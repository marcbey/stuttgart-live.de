import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["video", "button"]

  connect() {
    this.sync = this.sync.bind(this)

    if (this.hasVideoTarget) {
      this.videoTarget.addEventListener("volumechange", this.sync)
      this.videoTarget.addEventListener("loadedmetadata", this.sync)
    }

    this.sync()
  }

  disconnect() {
    if (!this.hasVideoTarget) return

    this.videoTarget.removeEventListener("volumechange", this.sync)
    this.videoTarget.removeEventListener("loadedmetadata", this.sync)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    if (!this.hasVideoTarget) return

    const shouldUnmute = this.videoTarget.muted
    this.videoTarget.muted = !shouldUnmute

    if (shouldUnmute) this.playVideo()

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
    if (!this.hasButtonTarget || !this.hasVideoTarget) return

    const unmuted = !this.videoTarget.muted
    this.buttonTarget.classList.toggle("is-unmuted", unmuted)
    this.buttonTarget.setAttribute("aria-pressed", unmuted ? "true" : "false")
    this.buttonTarget.setAttribute("aria-label", unmuted ? "Ton ausschalten" : "Ton einschalten")
  }
}
