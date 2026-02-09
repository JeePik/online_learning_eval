# config/importmap.rb

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true

pin_all_from "app/javascript/controllers", under: "controllers"

# Charts (Chartkick + Chart.js)
pin "chartkick", to: "chartkick.js"
pin "chart.js", to: "chart.js"
pin "chartkick/chart.js", to: "chartkick/chart.js"
pin "chartkick", to: "https://ga.jspm.io/npm:chartkick@5.0.1/dist/chartkick.js"
pin "chart.js", to: "https://ga.jspm.io/npm:chart.js@4.4.0/dist/chart.umd.js"
