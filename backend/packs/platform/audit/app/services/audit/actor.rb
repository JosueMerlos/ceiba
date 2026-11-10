module Audit
  # Who acts: the explicit principal, the request's or the context's; with none, the system. Every principal declares
  # its type with `actor_type` (Access::Principal contract); it is not guessed from the class name.
  Actor = Data.define(:type, :id) do
    SYSTEM = "system".freeze

    def self.resolve(explicit = nil)
      principal = explicit || Current.principal || Current.context&.principal
      return new(type: SYSTEM, id: nil) unless principal
      raise ArgumentError, "#{principal.class} debe declarar actor_type (contrato de los principales)" unless principal.respond_to?(:actor_type)

      new(type: principal.actor_type, id: principal.id)
    end
  end
end
