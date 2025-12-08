Rails.application.routes.draw do


 root 'pages#home'
  
  resources :accounts do
    member do
      post :switch
    end
  end
  
  # Dashboard
  get 'dashboard', to: 'pages#dashboard'
  
  # Transactions
  resources :transactions, only: [:index, :create, :show, :update]
  
  resources :users, only: [:index, :create, :show, :update, :destroy]
  post 'users/invite', to: 'users#invite'
  delete 'users/:id/remove', to: 'users#remove'
  
  # Settings
  get 'settings', to: 'settings#index'
  patch 'settings', to: 'settings#update'


  resource :session
  resources :passwords, param: :token


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
