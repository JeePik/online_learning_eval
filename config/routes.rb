Rails.application.routes.draw do
  get "quality/index"
  root "quality#index"

  post "calculate", to: "quality#calculate"
  get "download/:type", to: "quality#download", as: :download

   post "quality/calculate_subject_pairs", to: "quality#calculate_subject_pairs", as: :calculate_subject_pairs
  get  "quality/export_subject_pairs",    to: "quality#export_subject_pairs",    as: :export_subject_pairs
end
