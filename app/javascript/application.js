// app/javascript/application.js
import "@hotwired/turbo-rails"

/* =========================
   Chartkick: redraw after Turbo updates
========================= */

function redrawChartkick() {
  if (window.Chartkick && window.Chartkick.eachChart) {
    window.Chartkick.eachChart((chart) => chart.redraw())
  }
}

document.addEventListener("turbo:load", redrawChartkick)
document.addEventListener("turbo:render", redrawChartkick)
// (turbo:frame-load можна додати, але зазвичай не потрібно)

/* =========================
   Sticky offset var + scroll to "normalized"
========================= */

;(function () {
  let pendingScroll = false

  function setStickyOffsetVar() {
    const sticky = document.querySelector(
      ".sticky-menu, .sticky-nav, .navbar, .header-menu"
    )
    const offset = (sticky ? sticky.offsetHeight : 0) + 12
    document.documentElement.style.setProperty("--sticky-offset", `${offset}px`)
  }

  function scrollToNormalized() {
    const el = document.getElementById("normalized")
    if (!el) return
    setStickyOffsetVar()
    el.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  document.addEventListener("turbo:load", setStickyOffsetVar)
  window.addEventListener("resize", setStickyOffsetVar)

  // 1) Після успішного submit ставимо "прапорець", але НЕ скролимо тут
  document.addEventListener("turbo:submit-end", (event) => {
    const form = event.target
    if (!(form instanceof HTMLFormElement)) return
    if (form.id !== "calculate-form") return
    if (!event.detail?.success) return

    pendingScroll = true
  })

  // 2) Ловимо момент, коли Turbo Stream реально оновлює DOM
  document.addEventListener("turbo:before-stream-render", (event) => {
    if (!pendingScroll) return

    const stream = event.target
    if (!(stream instanceof Element)) return

    const target = stream.getAttribute("target")
    if (target !== "results") return

    const originalRender = event.detail.render
    event.detail.render = (streamEl) => {
      originalRender(streamEl)

      // DOM уже оновлено — тепер можна скролити
      requestAnimationFrame(() => requestAnimationFrame(scrollToNormalized))
      pendingScroll = false
    }
  })
})()

/* =========================
   Active anchors highlighting
========================= */

;(function () {
  function getStickyOffset() {
    const cssVar = getComputedStyle(document.documentElement)
      .getPropertyValue("--sticky-offset")
      .trim()
    const n = parseFloat(cssVar)
    return Number.isFinite(n) ? n : 96
  }

  function setActiveLink(hash) {
    document.querySelectorAll('a[href^="#"]').forEach((a) => {
      const active = a.getAttribute("href") === hash
      a.classList.toggle("is-active", active)
      a.setAttribute("aria-current", active ? "page" : "false")
    })
  }

  function initActiveAnchors() {
    const sections = Array.from(document.querySelectorAll("section[id]")).filter(
      (s) => s.id
    )
    if (!sections.length) return

    const offset = getStickyOffset()

    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries.filter((e) => e.isIntersecting)
        if (!visible.length) return

        visible.sort(
          (a, b) => a.boundingClientRect.top - b.boundingClientRect.top
        )
        setActiveLink(`#${visible[0].target.id}`)
      },
      {
        rootMargin: `-${offset}px 0px -60% 0px`,
        threshold: 0.2,
      }
    )

    sections.forEach((s) => observer.observe(s))

    if (location.hash) setActiveLink(location.hash)
  }

  document.addEventListener("turbo:load", initActiveAnchors)
  document.addEventListener("turbo:render", initActiveAnchors)
})()

/* =========================
   Custom file input
========================= */

document.addEventListener("turbo:load", () => {
  const input = document.getElementById("csv_file")
  const fileName = document.getElementById("file-name")
  const form = document.getElementById("calculate-form")

  if (!input || !fileName || !form) return

  const initialText = fileName.textContent

  // Показ назви файлу
  input.addEventListener("change", () => {
    fileName.textContent = input.files?.[0]?.name || initialText
  })

  // Кастомна валідація
  form.addEventListener("submit", (e) => {
    if (!input.files || input.files.length === 0) {
      e.preventDefault()
      showToast("Оберіть файл CSV перед обчисленням")
    }
  })
})

/* =========================
   Toast повідомлення
========================= */

function showToast(message) {
  const toast = document.createElement("div")
  toast.className = "toast-message"
  toast.textContent = message
  document.body.appendChild(toast)

  setTimeout(() => {
    toast.classList.add("show")
  }, 10)

  setTimeout(() => {
    toast.classList.remove("show")
    setTimeout(() => toast.remove(), 300)
  }, 3000)
}

