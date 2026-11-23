Rails.application.routes.draw do
  # Returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  resource :session, only: %i[new create destroy]

  resources :checks, path: "websites" do
    resource :pause, only: %i[create destroy]
  end

  resource :websites_file, path: "import-export", only: %i[show create]
  resource :board_link, path: "board-link", only: %i[show update]
  get "board/:token" => "boards#show", as: :board

  root "checks#index"
end
