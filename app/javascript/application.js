// app/javascript/application.js
// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails

import "@hotwired/turbo-rails"

// Після Turbo-переходів/рендерів просимо Chartkick перемалювати графіки
function redrawChartkick() {
  if (window.Chartkick && window.Chartkick.eachChart) {
    window.Chartkick.eachChart((chart) => chart.redraw())
  }
}

document.addEventListener("turbo:load", redrawChartkick)
document.addEventListener("turbo:render", redrawChartkick)


;(function () {
  function setStickyOffsetVar() {
  const sticky = document.querySelector(".sticky-menu, .sticky-nav, .navbar, .header-menu");
  const offset = (sticky ? sticky.offsetHeight : 0) + 12;
  document.documentElement.style.setProperty("--sticky-offset", `${offset}px`);
}

function scrollToNormalized() {
  const el = document.getElementById("normalized");
  if (!el) return;

  // 1) виставляємо актуальний відступ
  setStickyOffsetVar();

  // 2) скролимо з урахуванням scroll-margin-top
  el.scrollIntoView({ behavior: "smooth", block: "start" });
}

document.addEventListener("turbo:load", setStickyOffsetVar);
window.addEventListener("resize", setStickyOffsetVar);



  // ✅ Головний тригер: після завершення Turbo submit
  document.addEventListener("turbo:submit-end", (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement)) return;
  if (form.id !== "calculate-form") return;

  if (event.detail && event.detail.success) {
    requestAnimationFrame(() => requestAnimationFrame(scrollToNormalized));
  }

    // даємо Turbo Stream оновити DOM і тоді скролимо
    requestAnimationFrame(() => {
      requestAnimationFrame(scrollToNormalized)
    })
  })
})()

//Підсвітка активних якорів меню
;(function () {
  function getStickyOffset() {
    const cssVar = getComputedStyle(document.documentElement)
      .getPropertyValue("--sticky-offset")
      .trim()
    const n = parseFloat(cssVar)
    return Number.isFinite(n) ? n : 96
  }

  function setActiveLink(hash) {
    const links = document.querySelectorAll('a[href^="#"]')
    links.forEach((a) => {
      const isActive = a.getAttribute("href") === hash
      a.classList.toggle("is-active", isActive)
      a.setAttribute("aria-current", isActive ? "page" : "false")
    })
  }

  function initActiveAnchors() {
    // секції, які реально є на лендінгу
    const sections = Array.from(
      document.querySelectorAll("section[id]")
    ).filter((s) => s.id)

    if (sections.length === 0) return

    // якщо меню містить не всі секції — це ок, просто активуватимемо те, що є
    const offset = getStickyOffset()

    const observer = new IntersectionObserver(
      (entries) => {
        // беремо ті, що видимі
        const visible = entries.filter((e) => e.isIntersecting)
        if (visible.length === 0) return

        // вибираємо “найближчу” до верху (з урахуванням sticky)
        visible.sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)
        const top = visible[0].target
        setActiveLink(`#${top.id}`)
      },
      {
        root: null,
        // важливо: віднімаємо sticky offset, щоб секція ставала активною коректно
        rootMargin: `-${offset}px 0px -60% 0px`,
        threshold: [0.1, 0.2, 0.3],
      }
    )

    sections.forEach((s) => observer.observe(s))

    // ініціалізація по поточному hash (якщо є)
    if (location.hash) setActiveLink(location.hash)
  }

  document.addEventListener("turbo:load", initActiveAnchors)
  document.addEventListener("turbo:render", initActiveAnchors)
})()
