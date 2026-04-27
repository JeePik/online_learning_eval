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

/* =========================
   Clear only target container before submit
========================= */

document.addEventListener("turbo:submit-start", (event) => {
  const form = event.target
  if (!(form instanceof HTMLFormElement)) return

  let targetId = null

  if (form.id === "calculate-form") {
    targetId = "results"
  } else if (form.id === "subject-pairs-form") {
    targetId = "subject_pairs_results"
  }

  if (!targetId) return

  const target = document.getElementById(targetId)
  if (target) {
    target.innerHTML = ""
  }
})

/* =========================
   Sticky offset var + scroll to updated results
========================= */

;(function () {
  let pendingScrollTarget = null

  function setStickyOffsetVar() {
    const sticky = document.querySelector(
      ".sticky-menu, .sticky-nav, .navbar, .header-menu"
    )
    const offset = (sticky ? sticky.offsetHeight : 0) + 12
    document.documentElement.style.setProperty("--sticky-offset", `${offset}px`)
  }

  function scrollToTarget(targetId) {
    if (!targetId) return

    let el = null

    if (targetId === "results") {
      el = document.getElementById("normalized") || document.getElementById("results")
    } else if (targetId === "subject_pairs_results") {
      el = document.getElementById("subject-pairs-anchor") || document.getElementById("subject-pairs-normalized")
    }

    if (!el) return

    setStickyOffsetVar()
    el.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  document.addEventListener("turbo:load", setStickyOffsetVar)
  window.addEventListener("resize", setStickyOffsetVar)

  // Після успішного submit запам'ятовуємо, куди треба скролити
  document.addEventListener("turbo:submit-end", (event) => {
    const form = event.target
    if (!(form instanceof HTMLFormElement)) return
    if (!event.detail?.success) return

    if (form.id === "calculate-form") {
      pendingScrollTarget = "results"
    } else if (form.id === "subject-pairs-form") {
      pendingScrollTarget = "subject_pairs_results"
    }
  })

  // Ловимо оновлення саме потрібного Turbo Stream target
  document.addEventListener("turbo:before-stream-render", (event) => {
    if (!pendingScrollTarget) return

    const stream = event.target
    if (!(stream instanceof Element)) return

    const target = stream.getAttribute("target")
    if (target !== pendingScrollTarget) return

    const originalRender = event.detail.render
    event.detail.render = (streamEl) => {
      originalRender(streamEl)

      requestAnimationFrame(() => {
        requestAnimationFrame(() => scrollToTarget(target))
      })

      pendingScrollTarget = null
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
   Subject pairs form validation
========================= */

document.addEventListener("turbo:load", () => {
  const form = document.getElementById("subject-pairs-form")
  if (!form) return

  const input = form.querySelector('input[type="file"]')

  form.addEventListener("submit", (e) => {
    if (!input || !input.files || input.files.length === 0) {
      e.preventDefault()
      showToast("Оберіть CSV-файл для 5 пар")
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

/* =========================
   Subject pairs custom file input
========================= */

document.addEventListener("turbo:load", () => {
  const input = document.getElementById("subject_pairs_file")
  const fileName = document.getElementById("subject-pairs-file-name")

  if (!input || !fileName) return

  const initialText = fileName.textContent

  input.addEventListener("change", () => {
    fileName.textContent = input.files?.[0]?.name || initialText
  })
})