module Observability
  # Hace que cada Tenancy.with_context deje su contexto en Observability::LogContext.
  #
  # Se antepone (prepend) a Tenancy en lugar de editar tenancy.rb: el pack de tenancy no sabe de logs y el hook sigue
  # funcionando con cualquier firma de `with_context` (no la enumera: reenvía los argumentos tal cual). Lo instala
  # config/initializers/structured_logging.rb en `to_prepare` (tras cada recarga de código en desarrollo).
  module TenancyHook
    def with_context(...)
      return super unless block_given?

      super do |context|
        Observability::LogContext.remember(context)
        yield context
      end
    end
  end
end
