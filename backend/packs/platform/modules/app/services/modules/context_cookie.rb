module Modules
  # "Último contexto usado" de GET /api/v1/me: una cookie FIRMADA por navegador con `organización:empresa:sucursal`. Decisión (M0.09):
  # no se persiste en la base porque (1) un GET no escribe (corre en una transacción de solo lectura) y (2) el contexto recordado es
  # una conveniencia por dispositivo, no un dato del usuario. NO es una credencial: lo recordado se vuelve a validar contra los
  # memberships en cada uso (si el usuario perdió el acceso, se cae al contexto por defecto) y una cookie manipulada se ignora.
  module ContextCookie
    BASE_NAME = "ceiba_context".freeze
    LIFETIME = 90.days
    SEPARATOR = ":".freeze

    # La cookie va ligada al usuario (su id dentro del valor firmado): otra persona que inicie sesión en el mismo navegador no hereda el
    # contexto recordado de la anterior (y una cookie sobrante tras un logout no sirve a nadie más).
    Selection = Data.define(:organization_id, :company_id, :branch_id) do
      def serialize = [ organization_id, company_id, branch_id ].map(&:to_s).join(SEPARATOR)
    end

    module_function

    def name = Api::SessionCookie.secure? ? "#{Api::SessionCookie::HOST_PREFIX}#{BASE_NAME}" : BASE_NAME

    # La selección recordada o nil (ausente, manipulada, de otro usuario o con ids que no son UUID).
    def read(cookies, user_id:)
      value = cookies.signed[name]
      return unless value.is_a?(String)

      owner, organization_id, company_id, branch_id = value.split(SEPARATOR, -1).map(&:presence)
      return unless owner == user_id.to_s && organization_id && [ organization_id, company_id, branch_id ].compact.all? { |id| id.match?(/\A[0-9a-f-]{36}\z/) }

      Selection.new(organization_id:, company_id:, branch_id:)
    end

    # Solo escribe si cambió: no hay un Set-Cookie en cada request.
    def write(cookies, selection, user_id:)
      return if read(cookies, user_id:) == selection

      cookies.signed[name] = Api::SessionCookie.attributes.merge(value: "#{user_id}#{SEPARATOR}#{selection.serialize}", expires: LIFETIME.from_now)
    end
  end
end
