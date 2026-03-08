Rails.application.routes.draw do
  internal_framework_path = lambda do |request|
    framework_prefixes = [
      "/rails/",
      "/recede_historical_location",
      "/resume_historical_location",
      "/refresh_historical_location"
    ]

    framework_prefixes.none? { |prefix| request.path.start_with?(prefix) }
  end

  match "/400", to: "errors#show", via: :all, defaults: { code: 400 }
  match "/404", to: "errors#show", via: :all, defaults: { code: 404 }
  match "/422", to: "errors#show", via: :all, defaults: { code: 422 }
  match "/500", to: "errors#show", via: :all, defaults: { code: 500 }
  match "/errors/:code", to: "errors#show", via: :all

  resource :session, only: [ :new, :create, :destroy ]
  resources :passwords, param: :token, only: [ :show, :new, :create, :edit, :update ]

  namespace :backend do
    resource :account_password, only: [ :edit, :update ]
    resources :users, only: [ :index, :new, :create, :edit, :update ]

    resources :import_sources, only: [ :index, :edit, :update ] do
      post :sync_imported_events, on: :collection
      post :run_easyticket, on: :member
      post :stop_easyticket_run, on: :member
      post :run_eventim, on: :member
      post :stop_eventim_run, on: :member
      post :run_reservix, on: :member
      post :stop_reservix_run, on: :member
    end
    resources :import_runs, only: [ :show ] do
      post :add_filtered_city, on: :member
      post :remove_whitelist_city, on: :member
    end

    resources :events, only: [ :index, :show, :new, :create, :update ] do
      patch :publish, on: :member
      patch :unpublish, on: :member
      patch :bulk, on: :collection
      post :apply_filters, on: :collection
      post :next_event_preference, on: :collection
      post :sync_imported_events, on: :collection
      resources :event_images, only: [ :create, :update, :destroy ] do
        post :create_from_import, on: :collection
        delete :destroy_editorial_main, on: :collection
      end
    end
  end

  resources :events, only: [ :index, :show ], module: :public, param: :slug do
    patch :status, on: :member
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "backend", to: "backend/events#index", as: :backend_root

  root "public/events#index"

  match "*unmatched", to: "errors#show", via: :all, defaults: { code: 404 }, constraints: internal_framework_path
end
