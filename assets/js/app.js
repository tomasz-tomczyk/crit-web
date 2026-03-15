// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/crit"
import topbar from "../vendor/topbar"
// Load document-renderer (markdown-it + hljs + mermaid) only on review pages.
// Top-level await is valid in ES modules — it blocks module evaluation so the
// hook is ready synchronously when LiveView calls mounted().
const isReviewPage = window.location.pathname.startsWith('/r/')
const DocumentRendererHook = isReviewPage
  ? (await import("./document-renderer")).DocumentRenderer
  : { mounted() {} }

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, "CritWeb.ReviewLive.DocumentRenderer": DocumentRendererHook},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Theme switching
function setTheme(theme) {
  if (theme === "system") {
    localStorage.removeItem("phx:theme");
    document.documentElement.removeAttribute("data-theme");
  } else {
    localStorage.setItem("phx:theme", theme);
    document.documentElement.setAttribute("data-theme", theme);
  }
  document.querySelectorAll("[data-phx-theme]").forEach(btn => {
    btn.setAttribute("aria-checked", btn.dataset.phxTheme === theme ? "true" : "false");
  });
}

window.addEventListener("phx:set-theme", e => setTheme(e.target.dataset.phxTheme));
window.addEventListener("storage", e => e.key === "phx:theme" && setTheme(e.newValue || "system"));

// Mobile hamburger menu
document.getElementById("mobile-nav-toggle")?.addEventListener("click", () => {
  document.getElementById("mobile-nav")?.classList.toggle("hidden");
});

// connect if there are any LiveViews on the page
liveSocket.connect()

window.addEventListener("clipboard:copy", e => {
  navigator.clipboard.writeText(e.detail.text).catch(() => {})
  const btn = e.target
  const originalText = btn.textContent
  btn.textContent = "✓ Copied"
  setTimeout(() => { btn.textContent = originalText }, 2000)
})

// Close prompt dropdown when clicking outside
document.addEventListener('click', function(e) {
  const dropdown = document.getElementById('prompt-dropdown');
  const splitBtn = document.getElementById('prompt-split-btn');
  if (!dropdown || !splitBtn) return;
  if (!splitBtn.contains(e.target)) {
    dropdown.style.display = 'none';
  }
});

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// Home page: copy buttons
document.querySelectorAll(".copy-btn").forEach(btn => {
  const defaultIcon = btn.querySelector(".icon-default")
  const copiedIcon = btn.querySelector(".icon-copied")
  btn.addEventListener("click", () => {
    const raw = btn.previousElementSibling.textContent.trim()
    const text = raw.replace(/^\$\s+/, "")
    navigator.clipboard.writeText(text).then(() => {
      btn.style.color = "var(--crit-green)"
      defaultIcon.classList.add("hidden")
      copiedIcon.classList.remove("hidden")
      setTimeout(() => {
        btn.style.color = ""
        defaultIcon.classList.remove("hidden")
        copiedIcon.classList.add("hidden")
      }, 2000)
    })
  })
})

// Home page: YouTube lite facade — load iframe on click
const ytFacade = document.getElementById("yt-facade")
if (ytFacade) {
  const activate = () => {
    const iframe = document.createElement("iframe")
    iframe.src = "https://www.youtube.com/embed/w_Dswm2Ft-o?autoplay=1"
    iframe.title = "Crit demo"
    iframe.allow = "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
    iframe.allowFullscreen = true
    iframe.className = "absolute inset-0 w-full h-full"
    iframe.style.border = "0"
    ytFacade.replaceChildren(iframe)
    ytFacade.classList.remove("cursor-pointer", "group")
  }
  ytFacade.addEventListener("click", activate)
  ytFacade.addEventListener("keydown", e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); activate() }})
}

// Home page: feature cards scroll-triggered reveal
const featuresGrid = document.getElementById("features-grid")
if (featuresGrid) {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        const cards = featuresGrid.querySelectorAll(".feature-card")
        cards.forEach((card, i) => {
          setTimeout(() => card.classList.add("revealed"), i * 80)
        })
        const selfHosting = document.querySelector("#self-hosting-card .feature-card")
        if (selfHosting) {
          setTimeout(() => selfHosting.classList.add("revealed"), cards.length * 80)
        }
        observer.unobserve(entry.target)
      }
    })
  }, { threshold: 0.05 })
  observer.observe(featuresGrid)
}

// Home page: install tab switcher
document.querySelectorAll(".install-tab").forEach(tab => {
  tab.addEventListener("click", () => {
    document.querySelectorAll(".install-tab").forEach(t => {
      t.classList.remove("border-(--crit-accent)", "text-(--crit-accent)")
      t.classList.add("border-transparent", "text-(--crit-fg-muted)")
    })
    document.querySelectorAll(".install-panel").forEach(p => p.classList.add("hidden"))
    tab.classList.add("border-(--crit-accent)", "text-(--crit-accent)")
    tab.classList.remove("border-transparent", "text-(--crit-fg-muted)")
    document.getElementById(tab.dataset.target).classList.remove("hidden")
  })
})

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

