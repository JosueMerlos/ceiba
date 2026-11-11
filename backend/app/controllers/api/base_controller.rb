module Api
  # Base for the JSON API controllers: pack controllers inherit the problem+json rescues and mandatory authentication
  # (deny by default). The /api/health and /api/ready probes do not inherit from it: they are infrastructure.
  class BaseController < ApplicationController
    include ErrorHandling
    include RequestMetadata
    include Authentication
    include Access::Authorization
    include Paginated
    include TypedParams
  end
end
