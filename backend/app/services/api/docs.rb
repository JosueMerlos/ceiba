module Api
  # Swagger UI and the contract at /api/docs: only in development and test, and in staging if API_DOCS_ENABLED=true
  # (staging runs with RAILS_ENV=production). The routes do not exist in production.
  module Docs
    def self.enabled?(environment: Rails.env, flag: ENV.fetch("API_DOCS_ENABLED", nil))
      %w[development test].include?(environment.to_s) || flag == "true"
    end
  end
end
