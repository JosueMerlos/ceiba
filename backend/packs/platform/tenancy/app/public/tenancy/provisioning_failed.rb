module Tenancy
  # La provisión no se pudo completar y NO quedó nada a medias. Es un error de DOMINIO (no una excepción de base de
  # datos): `code` dice por qué y `message` es legible para mostrarlo a quien opera.
  #
  #   :slug_reserved  el slug es una palabra reservada (admin, api...)
  #   :slug_taken     otra empresa ya usa el slug (incluye la carrera entre dos provisiones simultáneas)
  #   :invalid        otro dato inválido; `details` lo desglosa por sección y campo
  class ProvisioningFailed < Error
    attr_reader :code, :details

    # details: { company: { slug: ["..."] } }
    def initialize(code, message, details: {})
      super(message)
      @code = code
      @details = details.freeze
    end
  end
end
