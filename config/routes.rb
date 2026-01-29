Rails.application.routes.draw do
  # Demo endpoints for OpenTelemetry testing
  root "demo#index"
  get "/log", to: "demo#log_action"
  get "/slow", to: "demo#slow_action"
  get "/error", to: "demo#error_action"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
  get "/health", to: proc { [200, {}, ["OK"]] }
end
