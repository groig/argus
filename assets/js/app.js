import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/argus"
import topbar from "../vendor/topbar"

const RelativeTime = {
  mounted() {
    this.update = () => {
      const timestamp = this.el.dataset.timestamp
      const value = new Date(timestamp)

      if (Number.isNaN(value.getTime())) return

      const seconds = Math.max(0, Math.floor((Date.now() - value.getTime()) / 1000))

      if (seconds < 60) {
        this.el.textContent = `${seconds}s ago`
      } else if (seconds < 3600) {
        this.el.textContent = `${Math.floor(seconds / 60)}m ago`
      } else if (seconds < 86400) {
        this.el.textContent = `${Math.floor(seconds / 3600)}h ago`
      } else {
        this.el.textContent = `${Math.floor(seconds / 86400)}d ago`
      }
    }

    this.update()
    this.timer = setInterval(this.update, 60000)
  },
  destroyed() {
    clearInterval(this.timer)
  }
}

const ClipboardCopy = {
  mounted() {
    this.el.addEventListener("click", async () => {
      const value = this.el.dataset.copyValue
      const toast = this.el.dataset.copyToast || "Copied to clipboard"

      if (!value) return

      try {
        await navigator.clipboard.writeText(value)
        window.dispatchEvent(new CustomEvent("argus:toast", {
          detail: {kind: "info", message: toast}
        }))
      } catch (_error) {
        window.dispatchEvent(new CustomEvent("argus:toast", {
          detail: {kind: "error", message: "Clipboard write failed"}
        }))
      }
    })
  }
}

const ToastViewport = {
  mounted() {
    this.listener = event => {
      const {kind = "info", message = ""} = event.detail || {}

      if (!message) return

      const toast = document.createElement("div")
      const icon = kind === "error" ? "hero-exclamation-circle" : "hero-information-circle"
      const tone = kind === "error"
        ? {
            border: "border-red-200",
            iconBg: "bg-red-100",
            iconColor: "text-red-700",
          }
        : {
            border: "border-sky-200",
            iconBg: "bg-sky-100",
            iconColor: "text-sky-700",
          }

      toast.className = `pointer-events-auto w-full max-w-sm border bg-white px-4 py-3 shadow-[0_14px_40px_rgba(15,23,42,0.12)] ${tone.border}`

      const row = document.createElement("div")
      row.className = "flex items-start gap-3"

      const iconWrap = document.createElement("div")
      iconWrap.className = `mt-0.5 flex h-7 w-7 items-center justify-center rounded-sm ${tone.iconBg}`

      const iconNode = document.createElement("span")
      iconNode.className = `${icon} size-4 ${tone.iconColor}`
      iconWrap.appendChild(iconNode)

      const body = document.createElement("div")
      body.className = "flex-1"

      const text = document.createElement("p")
      text.className = "text-sm leading-6 text-zinc-600"
      text.textContent = message

      body.appendChild(text)
      row.appendChild(iconWrap)
      row.appendChild(body)
      toast.appendChild(row)

      this.el.appendChild(toast)

      setTimeout(() => {
        toast.remove()
      }, 2200)
    }

    window.addEventListener("argus:toast", this.listener)
  },

  destroyed() {
    window.removeEventListener("argus:toast", this.listener)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {
    ...colocatedHooks,
    RelativeTime,
    ClipboardCopy,
    ToastViewport,
  },
})

topbar.config({barColors: {0: "#111827"}, shadowColor: "rgba(17, 24, 39, .15)"})
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", event => keyDown = event.key)
    window.addEventListener("keyup", () => keyDown = null)
    window.addEventListener("click", event => {
      if (keyDown === "c") {
        event.preventDefault()
        event.stopImmediatePropagation()
        reloader.openEditorAtCaller(event.target)
      } else if (keyDown === "d") {
        event.preventDefault()
        event.stopImmediatePropagation()
        reloader.openEditorAtDef(event.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
