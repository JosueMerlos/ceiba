module Idempotency
  # Principal type (user, api_key...): declared with `actor_type` (Access::Principal contract), not guessed from the
  # class name.
  module Actor
    def self.type_of(principal)
      raise ArgumentError, "#{principal.class} debe declarar actor_type (contrato de los principales)" unless principal.respond_to?(:actor_type)

      principal.actor_type
    end
  end
end
