module Modules
  # Un manifiesto no cumple las reglas de docs/architecture/05-module-system.md. Falla el arranque (o el test) con TODOS los
  # problemas encontrados, no solo el primero, para corregirlos de una vez.
  class InvalidManifest < Error
    attr_reader :key, :problems

    def initialize(key, problems)
      @key = key.to_s
      @problems = Array(problems).freeze
      super("Manifiesto #{@key.inspect} inválido:\n#{@problems.map { |problem| "- #{problem}" }.join("\n")}")
    end
  end
end
