Rails.application.routes.draw do
  # ── Admin dashboard (server-rendered web, NOT the JSON API) ──────────────────
  # Staff log in at /admin/login. Password reset is enabled: admins can visit
  # /admin/password/new to request a reset email. There is no public
  # registration — admins are provisioned via seeds or `rails console`.
  devise_for :admin_users,
             path: "admin",
             path_names: { sign_in: "login", sign_out: "logout" },
             controllers: {
               sessions: "admin/sessions",
               passwords: "admin/passwords"
             },
             skip: [ :registrations ]

  # Admin Google OAuth (server-side code flow)
  get "admin/auth/google",          to: "admin/google_auth#initiate", as: :admin_google_auth_initiate
  get "admin/auth/google/callback", to: "admin/google_auth#callback", as: :admin_google_auth_callback

  # `config.api_only = true` makes `resources` skip the :new and :edit form
  # routes (APIs don't render forms), but Administrate's New/Edit pages need
  # them with the conventional helper names (new_admin_user_path,
  # edit_admin_listing_path, ...). `namespace` would prefix the `:as` as
  # `admin_new_user`, so we use `scope` (path + module, no `:as` prefix) to get
  # the exact names. Declared BEFORE the resources so `/admin/users/new` is not
  # swallowed by the `/admin/users/:id` show route.
  scope path: "admin", module: "admin" do
    %i[categories listings reports users admin_users].each do |res|
      singular = res.to_s.singularize
      get "#{res}/new",      to: "#{res}#new",  as: "new_admin_#{singular}"
      get "#{res}/:id/edit", to: "#{res}#edit", as: "edit_admin_#{singular}"
    end
  end

  namespace :admin do
    resources :categories
    resources :listings do
      member do
        patch :take_down
        patch :restore
      end
    end
    resources :reports do
      member do
        patch :resolve
        patch :dismiss
        patch :take_down_target
        patch :warn_target
      end
    end
    resources :users do
      member do
        patch :block
        patch :unblock
        post :warn
      end
    end
    resources :user_warnings, only: [ :index, :show ]
    resources :blocks, only: [ :index, :show ]
    resources :admin_audit_logs, only: [ :index, :show ]
    resources :admin_users

    root to: "dashboard#index"
  end
  # Unique cable path so it doesn't collide with other Rails apps on the same Redis
  mount ActionCable.server => "/hatiwal-cable"

  # Swagger API docs at /api-docs — gated to signed-in admins (devise_for
  # :admin_users). Logged-out visitors are redirected to the admin login, so the
  # docs are never publicly visible.
  authenticate :admin_user do
    mount Rswag::Ui::Engine  => "/api-docs"
    mount Rswag::Api::Engine => "/api-docs"
  end

  mount_devise_token_auth_for "User", at: "api/v1/auth", controllers: {
    registrations: "api/v1/auth/registrations",
    sessions: "api/v1/auth/sessions",
    passwords: "api/v1/auth/passwords"
  }

  # Google OAuth for mobile — POST /api/v1/auth/google
  # Mobile sends a Google ID token; we verify it and return devise_token_auth tokens.
  post "api/v1/auth/google", to: "api/v1/auth/google_auth#create"

  namespace :api do
    namespace :v1 do
      # Public listing browser (buyer mode)
      resources :listings, only: [ :index, :show ] do
        member do
          post   :save
          delete :unsave
          post   :hide
          delete :unhide
          get    :similar
        end
        resources :conversations, only: [ :create ]
      end

      # Conversations (participant access)
      resources :conversations, only: [ :index, :show, :destroy ] do
        member do
          put :mark_read
          put :mark_unread
          put :archive
          put :unarchive
        end
        resources :messages, only: [ :index, :create, :destroy ] do
          collection do
            put :mark_read
          end
        end
      end

      # Categories
      resources :categories, only: [ :index ]

      # Reports
      resources :reports, only: [ :create, :index ]

      # User profiles
      namespace :users do
        get   "/me",          to: "profiles#me",        as: :me
        put   "/me",          to: "profiles#update_me"
        patch "/me",          to: "profiles#update_me"
        post  "/me/restore",  to: "profiles#restore",   as: :restore_me

        # Saved searches — MUST be declared before the "/:id" wildcard below,
        # otherwise GET /users/saved_searches is captured as profiles#show
        # with id="saved_searches" and 404s with RecordNotFound.
        get    "/saved_searches",              to: "saved_searches#index",     as: :saved_searches
        post   "/saved_searches",              to: "saved_searches#create"
        delete "/saved_searches/:id",          to: "saved_searches#destroy",   as: :saved_search
        put    "/saved_searches/:id/mark_seen", to: "saved_searches#mark_seen", as: :mark_seen_saved_search

        # The signed-in user's own moderation warnings (also before "/:id").
        get "/warnings",           to: "warnings#index",     as: :warnings
        put "/warnings/mark_seen", to: "warnings#mark_seen", as: :mark_warnings_seen

        get   "/:user_id/sold_listings", to: "sold_listings#index", as: :user_sold_listings
        get   "/:id/public_profile", to: "public_profiles#show", as: :public_profile
        get   "/:id", to: "profiles#show",       as: :profile
      end

      # Block / unblock a user  — POST/DELETE /users/:user_id/block
      # List the users the current user has blocked — GET /blocks
      get    "blocks",                 to: "blocks#index",   as: :blocks
      post   "users/:user_id/block",   to: "blocks#create",  as: :user_block
      delete "users/:user_id/block",   to: "blocks#destroy"

      # Seller / owner mode
      namespace :my do
        resources :listings do
          member do
            put :publish
            put :unpublish
            put :reserve
            put :activate
            put :sold
            put :renew
          end
          # GET /my/listings/:listing_id/analytics
          resource :analytics, only: [ :show ], controller: "listing_analytics"
          # GET /my/listings/status_counts — per-status counts for the seller.
          # Must be a COLLECTION route so it is matched BEFORE /my/listings/:id.
          collection do
            get :status_counts, to: "listing_status_counts#show"
          end
        end

        resources :saved_listings, only: [ :index ]
        resources :viewed_listings, only: [ :index ]
        resources :hidden_listings, only: [ :index ]
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
