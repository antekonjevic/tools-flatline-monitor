import { Controller } from "@hotwired/stimulus"

// Reloads the page every few seconds so it can be left open. Turbo morphs
// the new page into place, so scroll position is kept and nothing flickers.
export default class extends Controller {
  static values = { seconds: { type: Number, default: 30 } }

  connect() {
    this.lastRefresh = Date.now()
    this.timer = setInterval(() => this.tick(), 5000)
    this.onVisible = () => this.tick()
    document.addEventListener("visibilitychange", this.onVisible)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("visibilitychange", this.onVisible)
  }

  tick() {
    if (document.visibilityState !== "visible") return
    if (Date.now() - this.lastRefresh < this.secondsValue * 1000) return

    this.lastRefresh = Date.now()
    window.Turbo.visit(window.location.href, { action: "replace" })
  }
}
