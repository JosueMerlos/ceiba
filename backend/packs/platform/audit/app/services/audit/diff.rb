module Audit
  # Diff de atributos para audit_events (privacidad de la auditoría; criterio 5 de M0.11).
  #
  #   Audit::Diff.call(before: { "name" => "A" }, after: { "name" => "B" }, encrypted_attributes: [:phone])
  #   # => { before: { "name" => "A" }, after: { "name" => "B" } }
  #
  # - Con ambos lados guarda solo las claves cuyo valor cambió (o que aparecen/desaparecen). Una creación (before nil) o
  #   un borrado (after nil) conservan todo el lado presente.
  # - Campos SENSIBLES por nombre (password, token, secret, digest, csrf, otp...): se excluyen por completo, ni clave ni valor.
  # - PII CIFRADA (atributos que el sujeto declara con `encrypts`): se compara el valor real para saber si cambió, pero
  #   se guarda "[FILTERED]". Un cifrado que no cambió no aparece.
  class Diff
    FILTERED = "[FILTERED]".freeze
    SENSITIVE = /passw|token|secret|digest|csrf|otp|credential|api_key|private_key/i

    def self.call(...) = new(...).call

    def initialize(before:, after:, encrypted_attributes: [])
      @before = stringify(before)
      @after = stringify(after)
      @encrypted = Array(encrypted_attributes).map(&:to_s)
    end

    def call
      keys = changed_keys.reject { |key| SENSITIVE.match?(key) }
      { before: render(@before, keys), after: render(@after, keys) }
    end

    private

    def changed_keys
      return (@before || @after || {}).keys if @before.nil? || @after.nil?

      (@before.keys | @after.keys).reject { |key| @before.fetch(key, nil) == @after.fetch(key, nil) && @before.key?(key) == @after.key?(key) }
    end

    def render(side, keys)
      return if side.nil?

      side.slice(*keys).to_h { |key, value| [ key, @encrypted.include?(key) ? FILTERED : value ] }
    end

    def stringify(hash) = hash&.to_h { |key, value| [ key.to_s, value ] }
  end
end
