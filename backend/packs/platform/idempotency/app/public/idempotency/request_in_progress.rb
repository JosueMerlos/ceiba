module Idempotency
  # Another request with the same key is still running past the bounded wait: the client retries with the SAME key and
  # gets the stored response.
  class RequestInProgress < Error; end
end
