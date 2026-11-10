module Api
  # Mutation with query string parameters (see ApiRequestGuard). Answers 400.
  class QueryNotAllowed < StandardError; end
end
