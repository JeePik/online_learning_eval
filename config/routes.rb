Rails.application.routes.draw do
  get "quality/index"
  root "quality#index"

  post "calculate", to: "quality#calculate"
  get "download/:type", to: "quality#download", as: :download
end
