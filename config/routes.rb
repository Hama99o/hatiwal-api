Rails.application.routes.draw do
  # Unique cable path so it doesn't collide with other Rails apps on the same Redis
  mount ActionCable.server => "/hatiwal-cable"

  mount Rswag::Ui::Engine  => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"

  mount_devise_token_auth_for "User", at: "api/v1/auth", controllers: {
    registrations: "api/v1/auth/registrations"
  }

  namespace :api do
    namespace :v1 do
      # Public listing browser (buyer mode)
      resources :listings, only: [ :index, :show ] do
        member do
          post   :save
          delete :unsave
        end
        resources :conversations, only: [ :create ]
      end

      # Conversations (participant access)
      resources :conversations, only: [ :index, :show, :destroy ] do
        resources :messages, only: [ :index, :create ] do
          collection do
            put :mark_read
          end
        end
      end

      # Categories
      resources :categories, only: [ :index ]

      # Reports
      resources :reports, only: [ :create ]

      # User profiles
      namespace :users do
        get   "/me",  to: "profiles#me",        as: :me
        put   "/me",  to: "profiles#update_me"
        patch "/me",  to: "profiles#update_me"

        # Saved searches — MUST be declared before the "/:id" wildcard below,
        # otherwise GET /users/saved_searches is captured as profiles#show
        # with id="saved_searches" and 404s with RecordNotFound.
        get    "/saved_searches",     to: "saved_searches#index",   as: :saved_searches
        post   "/saved_searches",     to: "saved_searches#create"
        delete "/saved_searches/:id", to: "saved_searches#destroy", as: :saved_search

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
        end

        resources :saved_listings, only: [ :index ]
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
