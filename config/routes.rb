Rails.application.routes.draw do


 root 'pages#home'
  
  resources :accounts do
    member do
      get :switch
      delete :leave
    end
  end
  
  # Dashboard
  get 'dashboard', to: 'pages#dashboard'
  
  # Transactions
  resources :transactions, only: [:index, :create, :show, :update]
  
  resources :users, only: [:index, :create, :show, :update, :destroy]
  post 'users/invite', to: 'users#invite'
  delete 'users/:id/remove', to: 'users#remove'

  # Invitations
  resources :invitations, only: [:create, :destroy]

  # Invitation success met share opties (WhatsApp, QR, Copy, Email)
  get 'invitations/success', to: 'invitations#success', as: :invitation_success

  # Stap 1: Invitation openen (kan email vragen als niet ingevuld)
  get 'invitations/:token/open', to: 'invitations#open', as: :open_invitation

  # Stap 2: Email verificatie (voor WhatsApp/QR/Link flows)
  post 'invitations/:token/request_verification', to: 'invitations#request_email_verification', as: :request_email_verification_invitation
  get 'invitations/:token/verify/:verification_token', to: 'invitations#verify_email', as: :verify_invitation_email

  # Stap 3: Accept/Reject pagina (na verificatie)
  get 'invitations/:token/accept', to: 'invitations#show_accept', as: :accept_invitation
  post 'invitations/:token/accept', to: 'invitations#accept', as: :process_invitation
  post 'invitations/:token/reject', to: 'invitations#reject', as: :reject_invitation

  # Helper: Direct email versturen
  post 'invitations/:token/send_email', to: 'invitations#send_invitation_email', as: :send_email_invitation
  
  # Settings
  get 'settings', to: 'settings#index'
  patch 'settings', to: 'settings#update'

  resource :session
  resources :passwords, param: :token

    # Authentication routes
  get  "login",    to: "sessions#new"
  post "login",    to: "sessions#create"
  delete "logout", to: "sessions#destroy"
  
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
    constraints subdomain: 'www' do
      match "/(*path)", to: redirect { |params, req|
        "https://#{req.domain}#{req.fullpath}"
      }, via: :all
    end
  end

end
