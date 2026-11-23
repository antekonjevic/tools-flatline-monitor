import { Controller } from "@hotwired/stimulus"

// Switches between light, dark and following the device. The choice goes in
// a cookie so the server renders the next page in the right colors straight
// away, without a flash of the other theme.
export default class extends Controller {
  static targets = ["option"]

  choose({ params: { choice } }) {
    const root = document.documentElement
    const forced = choice === "light" || choice === "dark"

    if (forced) root.dataset.theme = choice
    else delete root.dataset.theme

    document.querySelector('meta[name="color-scheme"]')?.setAttribute("content", forced ? choice : "light dark")
    this.#remember(forced ? choice : null)

    this.optionTargets.forEach((option) => {
      option.setAttribute("aria-pressed", option.dataset.themeChoiceParam === choice)
    })
  }

  #remember(theme) {
    const secure = location.protocol === "https:" ? "; secure" : ""
    document.cookie = theme
      ? `theme=${theme}; path=/; max-age=31536000; samesite=lax${secure}`
      : `theme=; path=/; max-age=0; samesite=lax${secure}`
  }
}
