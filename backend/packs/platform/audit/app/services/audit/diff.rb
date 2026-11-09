module Audit
  # Diff de atributos para audit_events (privacidad de la auditoría; criterio 5 de M0.11).
  #
  #   Audit::Diff.call(before: { "name" => "A" }, after: { "name" => "B" }, encrypted_attributes: [:phone])
  #   # => { before: { "name" => "A" }, after: { "name" => "B" } }
  #
  # - Con ambos lados guarda solo las claves de primer nivel cuyo valor cambió (o que aparecen/desaparecen). Una creación
  #   (before nil) o un borrado (after nil) conservan todo el lado presente.
  # - SENSIBLES: se enmascaran como "[FILTERED]" con el MISMO criterio que los logs (`config.filter_parameters`: passw,
  #   email, secret, token, _key, crypt, salt, certificate, otp, ssn, cvv, cvc...) más digest, csrf y ciphertext, y de forma
  #   RECURSIVA (hashes y arrays anidados: un jsonb `settings: { whatsapp_token: … }` no se cuela). La clave se conserva: que
  #   cambió una contraseña es un hecho auditable; cuál era, no. Es un criterio por NOMBRE: coincide por subcadena, así que
  #   enmascara de más (p. ej. `footprint` contiene `otp`) y nunca de menos.
  # - PII CIFRADA (atributos que el sujeto declara con `encrypts`): se compara el valor real para saber si cambió, pero se
  #   guarda "[FILTERED]". Un cifrado que no cambió no aparece.
  class Diff
    FILTERED = ActiveSupport::ParameterFilter::FILTERED
    EXTRA_FILTERS = [ /digest/i, /csrf/i, /ciphertext/i ].freeze

    def self.call(...) = new(...).call

    def initialize(before:, after:, encrypted_attributes: [])
      @before = stringify(before)
      @after = stringify(after)
      @encrypted = Array(encrypted_attributes).map(&:to_s)
    end

    def call
      keys = changed_keys
      { before: render(@before, keys), after: render(@after, keys) }
    end

    private

    # Se lee en cada llamada: otro initializer puede ampliar filter_parameters después de cargar este archivo.
    def parameter_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters + EXTRA_FILTERS)

    def changed_keys
      return (@before || @after || {}).keys if @before.nil? || @after.nil?

      (@before.keys | @after.keys).reject { |key| @before.fetch(key, nil) == @after.fetch(key, nil) && @before.key?(key) == @after.key?(key) }
    end

    def render(side, keys)
      return if side.nil?

      parameter_filter.filter(side.slice(*keys)).to_h { |key, value| [ key, @encrypted.include?(key) ? FILTERED : value ] }
    end

    # Copia con claves de texto en todos los niveles (no muta lo recibido).
    def stringify(value)
      case value
      when Hash then value.to_h { |key, nested| [ key.to_s, stringify(nested) ] }
      when Array then value.map { |nested| stringify(nested) }
      else value
      end
    end
  end
end
