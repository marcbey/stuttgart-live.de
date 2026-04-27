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

  static_page_route = lambda do |request|
    slug = request.path_parameters[:slug].to_s
    next false unless slug.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)

    StaticPage.where(slug: slug).exists?
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    false
  end

  genre_lane_route = lambda do |request|
    Public::Events::LaneDirectory.routeable_genre_slug?(request.path_parameters[:lane_slug])
  end

  match "/400", to: "errors#show", via: :all, defaults: { code: 400 }
  match "/404", to: "errors#show", via: :all, defaults: { code: 404 }
  match "/422", to: "errors#show", via: :all, defaults: { code: 422 }
  match "/500", to: "errors#show", via: :all, defaults: { code: 500 }
  match "/errors/:code", to: "errors#show", via: :all

  get "/login", to: redirect("/session/new"), as: :login
  resource :session, only: [ :new, :create, :destroy ]
  resources :passwords, param: :token, only: [ :show, :new, :create, :edit, :update ]

  namespace :backend do
    resource :account_password, only: [ :edit, :update ]
    resource :meta_connection, only: [ :show ] do
      get :start
      get :start_instagram
      get :start_facebook
      get :callback
      patch :select_target
      post :refresh_status
    end
    resource :settings, only: [ :edit, :update ] do
      get :section, on: :collection
    end
    resources :blog_posts, path: "blog", except: [ :show ]
    resources :pages, except: [ :show ]
    resources :presenters, except: [ :show ] do
      get :bulk_new, on: :collection
      post :bulk_create, on: :collection
    end
    resources :venues, except: [ :show ] do
      get :autocomplete, on: :collection
    end
    resources :users, only: [ :index, :new, :create, :edit, :update ]

    resources :import_sources, only: [ :index, :edit, :update ] do
      post :sync_imported_events, on: :collection
      post :stop_merge_run, on: :collection
      post :run_llm_enrichment, on: :collection
      post :rerun_llm_enrichment, on: :collection
      post :stop_llm_enrichment_run, on: :collection
      post :run_llm_genre_grouping, on: :collection
      post :stop_llm_genre_grouping_run, on: :collection
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
      post :run_llm_enrichment, on: :member
      resources :event_social_posts, path: "social_posts", only: [ :create, :update ] do
        post :quick_publish, on: :collection
        post :publish, on: :member
        post :regenerate, on: :member
      end
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
    get :saved_lane, on: :collection
    get :search_overlay, on: :collection
    get :termine, on: :member
    patch :status, on: :member
  end
  get "search", to: "public/events#search", as: :search
  get "deine-events", to: "public/events#saved", as: :saved_events
  get "highlights", to: "public/events#lane", defaults: { lane: "highlights" }, as: :highlights_lane
  get "russ-live", to: "public/events#lane", defaults: { lane: "russ_live" }, as: :russ_live_lane
  get "alles-aus-stuttgart", to: "public/events#lane", defaults: { lane: "all_stuttgart" }, as: :all_stuttgart_lane
  get "tagestipp", to: "public/events#lane", defaults: { lane: "tagestipp" }, as: :tagestipp_lane
  resources :newsletter_subscribers, only: [ :create ], module: :public
  get "kontakt", to: "public/pages#show", defaults: { slug: "kontakt" }, as: :contact
  get "impressum", to: "public/pages#show", defaults: { slug: "impressum" }, as: :imprint
  get "blog/:slug", to: "public/legacy_blog_redirects#show", as: :legacy_blog_redirect
  resources :news, only: [ :index, :show ], module: :public, param: :slug
  get "datenschutz", to: "public/pages#show", defaults: { slug: "datenschutz" }, as: :datenschutz
  get "agb", to: "public/pages#show", defaults: { slug: "agb" }, as: :agb
  get "barrierefreiheit", to: "public/pages#show", defaults: { slug: "barrierefreiheit" }, as: :barrierefreiheit
  get "begleitformular", to: "public/pages#guardian_form", as: :begleitformular

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "backend", to: "backend/events#index", as: :backend_root

  root "public/events#index"

  get ":lane_slug", to: "public/events#lane", as: :genre_lane, constraints: genre_lane_route
  get ":slug", to: "public/pages#show", as: :static_page, constraints: static_page_route

  match "*unmatched", to: "errors#show", via: :all, defaults: { code: 404 }, constraints: internal_framework_path
end
