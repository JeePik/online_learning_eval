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
