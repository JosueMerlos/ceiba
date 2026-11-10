module Api
  # Mutation body that is not application/json. Answers 415 (see ApiRequestGuard).
  class UnsupportedMediaType < StandardError; end
end
