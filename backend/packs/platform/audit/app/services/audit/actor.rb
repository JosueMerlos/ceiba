module Audit
  # Quién actúa: el principal explícito, el de la request o el del contexto; sin ninguno, el sistema. Todo principal declara
  # su tipo con `actor_type` (contrato de Access::Principal): no se adivina por el nombre de su clase.
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
