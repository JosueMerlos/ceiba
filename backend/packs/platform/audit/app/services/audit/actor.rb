module Audit
  # Quién actúa: el principal explícito, el de la request o el del contexto; sin ninguno, el sistema.
  Actor = Data.define(:type, :id) do
    SYSTEM = "system".freeze

    def self.resolve(explicit = nil)
      principal = explicit || Current.principal || Current.context&.principal
      return new(type: SYSTEM, id: nil) unless principal

      new(type: principal.try(:actor_type) || principal.class.name.demodulize.underscore, id: principal.id)
    end
  end
end
