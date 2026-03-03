Rails.application.routes.draw do
  resource :session, only: [ :new, :create, :destroy ]
  resources :passwords, param: :token, only: [ :new, :create, :edit, :update ]

  namespace :backend do
    resources :import_sources, only: [ :index, :edit, :update ] do
      post :run_easyticket, on: :member
      post :stop_easyticket_run, on: :member
      post :run_eventim, on: :member
      post :stop_eventim_run, on: :member
    end
    resources :import_runs, only: [ :show ] do
      post :add_filtered_city, on: :member
      post :remove_whitelist_city, on: :member
    end

    resources :events, only: [ :index, :show, :new, :create, :update ] do
      patch :publish, on: :member
      patch :unpublish, on: :member
      patch :bulk, on: :collection
      post :sync_imported_events, on: :collection
    end
  end

  resources :events, only: [ :index, :show ], module: :public, param: :slug

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "backend", to: "backend/events#index", as: :backend_root

  root "public/events#index"
end
