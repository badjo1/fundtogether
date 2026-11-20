Rails.application.routes.draw do
 root "pages#home"

  resources :accounts, only: [ :new, :create, :update, :destroy ] do
    member do
      post :switch
      delete :leave
    end

    # On-chain layer, JSON unless stated (docs/ARCHITECTURE.md, Browser/server contract)
    resource :safe, only: [ :show, :create, :update ], controller: "safes"
    resource :balance, only: :show
    resources :proposals, only: [ :index, :show, :create, :destroy ], controller: "safe_proposals" do
      resources :signatures, only: :create, controller: "safe_signatures"
      resource :execution, only: :create, controller: "safe_executions"
    end
    resources :sync_requests, only: :create
    resources :chain_events, only: :index

    # Pages. The JSON contract above keeps its own URLs, so one URL never answers in two formats.
    get "uitnodigen", to: "fund_invites#show", as: :invite
    get "safe_instellen", to: "safe_setup_pages#show", as: :safe_setup
    get "inleggen", to: "contribute_pages#show", as: :contribute
    get "inleggen/recent", to: "contribute_pages#recent", as: :contribute_recent
    get "activiteit", to: "activity_pages#show", as: :activity
    get "transparantie", to: "transparency_pages#show", as: :transparency
    resources :proposal_pages, path: "voorstellen", only: [ :index, :new, :create, :show ] do
      collection { get :list }
      member do
        get :live
        post :reject
        post :cancel
        post :renumber
      end
    end
    # Lazy turbo frames: live chain reads, so a slow RPC never blocks a page.
    get "live/balance", to: "live#balance", as: :live_balance
    get "live/owners", to: "live#owners", as: :live_owners
    get "live/attention", to: "live#attention", as: :live_attention

    # Ramp page: link-outs and instructions (docs/RAMPS.md)
    resource :ramp, only: :show, controller: "ramps" do
      get :leave
    end
  end

  resources :wallet_challenges, only: :create
  resources :wallets, only: [ :index, :create, :destroy ]
  resources :wallet_handoffs, only: :create
  get "wallet/handoff/:token", to: "wallet_handoff_redemptions#show", as: :wallet_handoff
  post "wallet/handoff/:token", to: "wallet_handoff_redemptions#create"
  get "wallet", to: "wallet_pages#show", as: :wallet_page
  post "wallet/handoff", to: "wallet_pages#handoff", as: :wallet_page_handoff
  get "wallet/:id/eigenaarschap", to: "wallet_pages#ownership", as: :wallet_page_ownership
  delete "wallet/:id", to: "wallet_pages#unlink", as: :wallet_page_unlink

  # Dashboard
  get "dashboard", to: "pages#dashboard"

  resources :users, only: [ :index, :update, :destroy ]

  # Invitations
  resources :invitations, only: [ :create, :destroy ]

  # Invitation success met share opties (WhatsApp, QR, Copy, Email)
  get "invitations/success", to: "invitations#success", as: :invitation_success

  # Stap 1: Invitation openen (kan email vragen als niet ingevuld)
  get "invitations/:token/open", to: "invitations#open", as: :open_invitation

  # Stap 2: Email verificatie (voor WhatsApp/QR/Link flows)
  post "invitations/:token/request_verification", to: "invitations#request_email_verification", as: :request_email_verification_invitation
  get "invitations/:token/verify/:verification_token", to: "invitations#verify_email", as: :verify_invitation_email

  # Stap 3: Accept/Reject pagina (na verificatie)
  get "invitations/:token/accept", to: "invitations#show_accept", as: :accept_invitation
  post "invitations/:token/accept", to: "invitations#accept", as: :process_invitation
  post "invitations/:token/reject", to: "invitations#reject", as: :reject_invitation

  # Helper: Direct email versturen
  post "invitations/:token/send_email", to: "invitations#send_invitation_email", as: :send_email_invitation

  # Settings
  get "settings", to: "settings#index"
  patch "settings", to: "settings#update"

  resource :session
  get "sessies", to: "user_sessions#index", as: :sessions_list
  delete "sessies", to: "user_sessions#destroy_others", as: :sessions_revoke_others
  delete "sessies/:id", to: "user_sessions#destroy", as: :session_revoke
  resources :passwords, param: :token

  # Authentication routes
  get  "login",    to: "sessions#new"
  post "login",    to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  # E-mailbevestiging. GET toont alleen een pagina: mailscanners volgen links.
  get  "email_bevestigen", to: "email_confirmations#pending", as: :email_confirmation_pending
  post "email_bevestigen/opnieuw", to: "email_confirmations#resend", as: :resend_email_confirmation
  get  "email_bevestigen/:token", to: "email_confirmations#show", as: :email_confirmation
  post "email_bevestigen/:token", to: "email_confirmations#create"

  get  "register", to: "registrations#new"
  post "register", to: "registrations#create"


  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Redirect www to non-www in production
  if Rails.env.production?
    constraints subdomain: "www" do
      match "/(*path)", to: redirect { |params, req|
        "https://#{req.domain}#{req.fullpath}"
      }, via: :all
    end
  end
end
