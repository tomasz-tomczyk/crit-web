export async function initArticleMermaid() {
  const blocks = document.querySelectorAll(".article-body pre.mermaid")
  if (!blocks.length) return

  const { default: mermaid } = await import("mermaid")
  const attr = document.documentElement.dataset.theme
  const isLight =
    attr === "light" ||
    (!attr && window.matchMedia("(prefers-color-scheme: light)").matches)
  const theme = isLight ? "default" : "dark"

  mermaid.initialize({ startOnLoad: false, theme })

  let counter = 0
  for (const el of blocks) {
    const id = `article-mermaid-${counter++}`
    try {
      const { svg } = await mermaid.render(id, el.textContent.trim())
      const wrapper = document.createElement("div")
      wrapper.className = "mermaid-rendered"
      wrapper.innerHTML = svg
      el.replaceWith(wrapper)
    } catch {
      // Leave the source block visible if rendering fails.
    }
  }
}
