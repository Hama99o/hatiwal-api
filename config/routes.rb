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
    # VER-1: the verification queue. `document` streams one ID photo for a
    # token that expires in 5 minutes; every view is audit-logged.
    # SHOP-1 — shops: moderate, not edit.
    resources :shops, only: %i[index show] do
      member do
        patch :suspend
        patch :reactivate
        post :remove_badge
        delete "members/:member_id", action: :remove_member, as: :remove_member
      end
    end
    # UPD-1 — "App versions": force update / reminder settings + old-version message
    resource :app_versions, only: %i[show update] do
      post :message_old_versions
    end
    resources :verification_requests, only: %i[index show] do
      member do
        patch :approve
        patch :reject
        patch :revoke
        # Reveal the full ID number for this request only (audit-logged, no-store).
        post :reveal_number
        get "document/:token", action: :document, as: :document, constraints: { token: %r{[^/]+} }
      end
      collection do
        # Remove a badge that has no approved request behind it (switched on by hand).
        post :revoke_badge
      end
    end
    # One place to message one person (email / in-app / both) and see every
    # send. Admin::SendMessage does the sending.
    resources :messages, only: %i[index new create show] do
      collection do
        post :preview
        post :test
      end
    end
    # Bulk email to a filtered segment of users (email only).
    resources :bulk_emails, only: %i[new create show] do
      collection do
        post :preview
        post :test
      end
      member do
        patch :stop
        patch :resume
      end
    end
    resources :support_conversations, only: [ :index, :show ] do
      member do
        post  :reply
        patch :close
        patch :reopen
      end
    end
    resources :blocks, only: [ :index, :show ]
    resources :admin_audit_logs, only: [ :index, :show ]
    resources :admin_users

    root to: "dashboard#index"
  end
  # Public, no-login unsubscribe from bulk email (UnsubscribesController). The
  # token is a signed user id; POST is also the RFC 8058 one-click target.
  constraints token: %r{[^/]+} do
    get  "unsubscribe/:token",      to: "unsubscribes#show",   as: :unsubscribe
    post "unsubscribe/:token",      to: "unsubscribes#create"
    post "unsubscribe/:token/undo", to: "unsubscribes#undo",   as: :undo_unsubscribe
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
    passwords: "api/v1/auth/passwords",
    # Confirmations are overridden ONLY to make the post-confirm redirect legal:
    # DTA redirects to WEB_CONFIRM_URL, and Rails 7 raises on a cross-host
    # redirect, so clicking the link in the email returned 500 while the account
    # was in fact confirmed.
    confirmations: "api/v1/auth/confirmations"
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

      # The caller's own thread with Hatiwal Support (find-or-create). Additive;
      # only the app version with support messaging calls it.
      resource :support_conversation, only: [ :create ]

      # Categories
      resources :categories, only: [ :index ]

      # UPD-1 — force update / update reminder (public)
      get "app_config", to: "app_configs#show", as: :app_config

      # Reports
      resources :reports, only: [ :create, :index ]

      # SHOP-1 — shops (hatiwal-mobile/docs/SHOPS.md)
      resources :shops, only: %i[index show create update destroy] do
        member { post :move_listings }
        # The SHOP's reviews: buyers' reviews of sales of its products (public).
        resources :reviews, only: %i[index], controller: "shop_reviews"
        # SHOP-2 — "Message shop" from the shop page (no product): find-or-create.
        resources :conversations, only: %i[create], controller: "shop_conversations"
        # SHOP-3 — the team.
        resources :members, only: %i[index update destroy], controller: "shop_members", param: :user_id
        delete :membership, to: "shop_members#leave"
        post :transfer, to: "shop_members#transfer"
        resources :invites, only: %i[index create destroy], controller: "shop_invites" do
          member { post :resend }
        end
      end
      # SHOP-3 — opening an invitation (the token is the only key; public GET).
      resources :shop_invites, only: %i[show], param: :token, controller: "shop_invite_tokens" do
        member do
          post :accept
          post :decline
        end
      end

      # Reviews (double-blind, on a sold Transaction)
      resources :transactions, only: [] do
        # POST /api/v1/transactions/:transaction_id/reviews
        resources :reviews, only: [ :create ]
      end
      # PATCH /api/v1/reviews/:id — edit your own review while still hidden
      resources :reviews, only: [ :update ]
      # GET /api/v1/users/:user_id/reviews — a user's visible reviews (public)
      get "users/:user_id/reviews", to: "reviews#index", as: :user_reviews

      # VER-1: apply for the Verified badge. Responses carry the status card,
      # never a document.
      resources :verification_requests, only: %i[create destroy] do
        collection { get :current }
      end

      # User profiles
      namespace :users do
        get   "/me",          to: "profiles#me",        as: :me
        put   "/me",          to: "profiles#update_me"
        patch "/me",          to: "profiles#update_me"
        post  "/me/restore",  to: "profiles#restore",   as: :restore_me
        # LOC-1 — a clue about where the user is (never their own address).
        patch "/me/location_guess", to: "location_guesses#update", as: :me_location_guess
        # SHOP-1 — who the user sells as (null = Me).
        patch "/me/selling_as", to: "selling_as#update", as: :me_selling_as

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
        get "shops", to: "shops#index", as: :shops
        # Invitations addressed to my confirmed email (answer by token).
        get "shop_invites", to: "shop_invites#index", as: :shop_invites
        resources :listings do
          member do
            put :publish
            put :unpublish
            put :reserve
            put :activate
            put :sold
            put :renew
            put :relaunch
            put :move
            post :duplicate
          end
          # GET /my/listings/:listing_id/analytics
          resource :analytics, only: [ :show ], controller: "listing_analytics"
          # GET /my/listings/status_counts — per-status counts for the seller.
          # Must be a COLLECTION route so it is matched BEFORE /my/listings/:id.
          collection do
            get :status_counts, to: "listing_status_counts#show"
            # "Relaunch all" (item 2): every expired listing of Me / a shop.
            post :relaunch_expired, to: "analytics#relaunch_expired"
          end
        end

        # GET /my/analytics?shop_id= — a seller's numbers, Me or one shop (item 2).
        resource :analytics, only: [ :show ], controller: "analytics"
        resources :saved_listings, only: [ :index ]
        resources :viewed_listings, only: [ :index ]
        resources :hidden_listings, only: [ :index ]
        # GET    /my/transactions      — the caller's own transactions, as buyer or seller (TASK-TX01).
        # PATCH  /my/transactions/:id   — correct a recorded sale (quantity / buyer / price) (SF-B4).
        # DELETE /my/transactions/:id   — void a recorded sale, restoring stock and counters (SF-B4).
        resources :transactions, only: [ :index, :update, :destroy ]
        # GET /my/reviews/pending — sold sales the caller still owes a review on.
        get "reviews/pending", to: "reviews#pending"
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
