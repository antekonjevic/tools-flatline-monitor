import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    const text = this.sourceTarget.value

    try {
      await navigator.clipboard.writeText(text)
    } catch {
      this.sourceTarget.select()
      document.execCommand("copy")
    }

    this.buttonTarget.textContent = "Copied"
    setTimeout(() => { this.buttonTarget.textContent = "Copy" }, 2000)
  }
}
