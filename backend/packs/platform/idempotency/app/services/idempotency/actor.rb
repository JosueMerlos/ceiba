module Idempotency
  # Tipo del principal (user, api_key...): lo declara con `actor_type` (contrato de Access::Principal), no se adivina por el
  # nombre de su clase.
  module Actor
    def self.type_of(principal)
      raise ArgumentError, "#{principal.class} debe declarar actor_type (contrato de los principales)" unless principal.respond_to?(:actor_type)

      principal.actor_type
    end
  end
end
