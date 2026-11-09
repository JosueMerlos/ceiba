module Idempotency
  # Tipo del principal (user, api_key, platform_staff...): lo declara con `actor_type` o se deriva del nombre de su clase.
  module Actor
    def self.type_of(principal) = principal.try(:actor_type) || principal.class.name.demodulize.underscore
  end
end
