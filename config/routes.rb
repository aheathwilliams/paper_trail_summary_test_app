Rails.application.routes.draw do
  root "demo#show"
  post "reset", to: "demo#reset", as: :reset_demo
  get "report", to: "reports#show", as: :report

  resources :articles, only: %i[create update] do
    resources :comments, only: %i[create update destroy] do
      resources :replies, only: %i[create update destroy]
    end
    resources :authorships, only: %i[create destroy]
    resources :taggings, only: %i[create destroy]
    resources :document_revisions, only: %i[create update destroy]
  end
  resources :authors, only: %i[create update]
  resources :tags, only: %i[create update]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
