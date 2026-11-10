module Api
  module Pagination
    # Base for pagination errors: all are 400 (the client sent an invalid parameter).
    class Error < StandardError; end
  end
end
