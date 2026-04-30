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

// Sentry — only loaded when the server emits a <meta name="sentry-dsn">.
// Self-hosted users without a DSN incur no network calls and the dynamic
// import is skipped entirely (esbuild keeps it as a separate chunk).
function initSentry(liveSocket) {
  const sentryDsn = document.querySelector("meta[name='sentry-dsn']")?.content
  if (!sentryDsn) return
  const env = document.querySelector("meta[name='sentry-environment']")?.content
  const release = document.querySelector("meta[name='sentry-release']")?.content
  import("@sentry/browser").then(Sentry => {
    Sentry.init({
      dsn: sentryDsn,
      environment: env || "production",
      release: release || undefined,
      tracesSampleRate: 0,
      // Privacy: never attach personal data, never record DOM/inputs.
      sendDefaultPii: false,
      // Replace the default Breadcrumbs integration with one that doesn't
      // capture console output or DOM text — review/comment content must not leak.
      integrations: defaults => [
        ...defaults.filter(i => i.name !== "Breadcrumbs"),
        Sentry.breadcrumbsIntegration({
          console: false,
          dom: false,
          fetch: true,
          xhr: true,
          history: true,
          sentry: true,
        }),
      ],
      beforeSend(event) {
        // Mermaid/markdown errors quote the offending source verbatim — truncate.
        const ex = event.exception?.values?.[0]
        if (ex?.value && ex.value.length > 200) {
          ex.value = ex.value.slice(0, 200) + "…[truncated]"
        }
        return event
      },
      beforeBreadcrumb(crumb) {
        // Defense in depth — these should already be off via integration config.
        if (["console", "ui.click", "ui.input"].includes(crumb.category)) return null
        return crumb
      },
    })

    // LiveView socket errors hit console.error, not window.onerror —
    // wire them to Sentry explicitly. onError fires on every reconnect
    // backoff tick during outages, so dedupe until the next successful open.
    const socket = liveSocket?.getSocket?.()
    if (socket) {
      let reported = false
      socket.onError(err => {
        if (reported) return
        reported = true
        Sentry.captureMessage("LiveSocket transport error", {
          level: "error",
          extra: { type: err?.type, message: String(err?.message ?? err) },
        })
      })
      socket.onOpen(() => { reported = false })
    }
  }).catch(() => {})
}

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

// Site header identity popover: close on outside-click / Escape.
// Marketing pages are dead views (controller-rendered), so phx-hook
// won't reliably fire here — use document-level delegation instead.
// The popover open/close itself is handled by phx-click + JS.toggle_attribute,
// which works on dead views too (LiveSocket binds those globally).
document.addEventListener("click", e => {
  const popover = document.getElementById("site-identity-popover")
  const trigger = document.getElementById("site-identity-toggle")
  if (!popover || popover.hidden) return
  if (popover.contains(e.target) || trigger?.contains(e.target)) return
  popover.hidden = true
  trigger?.setAttribute("aria-expanded", "false")
})
document.addEventListener("keydown", e => {
  if (e.key !== "Escape") return
  const popover = document.getElementById("site-identity-popover")
  if (!popover || popover.hidden) return
  popover.hidden = true
  document.getElementById("site-identity-toggle")?.setAttribute("aria-expanded", "false")
})

// connect if there are any LiveViews on the page
liveSocket.connect()
initSentry(liveSocket)

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

// Unified copy buttons + tab switchers via document-level delegation.
// Marketing pages are dead views patched by <.link navigate>, so direct
// listeners attached at load don't survive DOM swaps. Delegation works
// regardless of when the matching elements appear.
document.addEventListener("click", e => {
  const btn = e.target.closest(".copy-btn")
  if (!btn) return
  if (btn.closest("#empty-state")) return
  const text = btn.dataset.copy
  if (!text) return
  const defaultIcon = btn.querySelector(".icon-default")
  const copiedIcon = btn.querySelector(".icon-copied")
  navigator.clipboard.writeText(text).then(() => {
    btn.style.color = "var(--crit-green)"
    if (defaultIcon && copiedIcon) {
      defaultIcon.classList.add("hidden")
      copiedIcon.classList.remove("hidden")
    }
    setTimeout(() => {
      btn.style.color = ""
      if (defaultIcon && copiedIcon) {
        defaultIcon.classList.remove("hidden")
        copiedIcon.classList.add("hidden")
      }
    }, 2000)
  })
})

// Tab switchers: .install-tab / .agent-tab. Each clicked tab activates itself
// and reveals the panel referenced by data-target, hiding sibling panels.
// Sibling tabs/panels are scoped by the shared class (install-* / agent-*).
function activateTab(tab, tabClass, panelClass) {
  document.querySelectorAll(`.${tabClass}`).forEach(t => {
    t.classList.remove("border-(--crit-brand)", "text-(--crit-brand)")
    t.classList.add("border-transparent", "text-(--crit-fg-muted)")
  })
  document.querySelectorAll(`.${panelClass}`).forEach(p => p.classList.add("hidden"))
  tab.classList.add("border-(--crit-brand)", "text-(--crit-brand)")
  tab.classList.remove("border-transparent", "text-(--crit-fg-muted)")
  const panel = document.getElementById(tab.dataset.target)
  if (panel) panel.classList.remove("hidden")
}

document.addEventListener("click", e => {
  const installTab = e.target.closest(".install-tab")
  if (installTab && !installTab.closest("#empty-state")) {
    activateTab(installTab, "install-tab", "install-panel")
    return
  }
  const agentTab = e.target.closest(".agent-tab")
  if (agentTab && !agentTab.closest("#empty-state")) {
    activateTab(agentTab, "agent-tab", "agent-panel")
  }
})

// Home page: YouTube lite facade — load iframe on click
const ytFacade = document.getElementById("yt-facade")
if (ytFacade) {
  const activate = () => {
    const iframe = document.createElement("iframe")
    iframe.src = "https://www.youtube.com/embed/LHwfdvePf5A?autoplay=1"
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

// Home page: testimonials scroll-triggered reveal
const testimonialsGrid = document.getElementById("testimonials-grid")
if (testimonialsGrid) {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        testimonialsGrid.querySelectorAll(".feature-card").forEach((card, i) => {
          setTimeout(() => card.classList.add("revealed"), i * 150)
        })
        observer.unobserve(entry.target)
      }
    })
  }, { threshold: 0.1 })
  observer.observe(testimonialsGrid)
}

// (Integration tab bar removed; per-tool pages don't use tabs.)

// Home page: platform stats count-up + staggered reveal
const platformStats = document.getElementById("platform-stats")
if (platformStats) {
  const formatWithCommas = n => n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  const formatBytes = bytes => {
    if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`
    if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(1)} MB`
    if (bytes >= 1e3) return `${Math.round(bytes / 1e3)} KB`
    return `${bytes} B`
  }

  const countUp = (el, target, formatter, duration = 1200) => {
    const start = performance.now()
    const step = now => {
      const t = Math.min((now - start) / duration, 1)
      // ease-out cubic
      const eased = 1 - Math.pow(1 - t, 3)
      el.textContent = formatter(Math.round(eased * target))
      if (t < 1) requestAnimationFrame(step)
    }
    requestAnimationFrame(step)
  }

  const statsObserver = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        // Staggered reveal
        platformStats.querySelectorAll(".stat-item, .stat-divider").forEach((el, i) => {
          setTimeout(() => el.classList.add("revealed"), i * 100)
        })

        // Count-up after first item reveals
        setTimeout(() => {
          platformStats.querySelectorAll("[data-count-to]").forEach(el => {
            countUp(el, parseInt(el.dataset.countTo, 10), formatWithCommas)
          })
          platformStats.querySelectorAll("[data-count-bytes]").forEach(el => {
            countUp(el, parseInt(el.dataset.countBytes, 10), formatBytes)
          })
        }, 150)

        statsObserver.unobserve(entry.target)
      }
    })
  }, { threshold: 0.2 })
  statsObserver.observe(platformStats)
}

// (.install-tab / .agent-tab handled by document-level delegation above.)

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

