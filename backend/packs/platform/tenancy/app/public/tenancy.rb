# API pública del pack platform/tenancy (junto con Tenancy::Context, Tenancy::ProvisionOrganization y los errores).
module Tenancy
  SETTING = "app.organization_id".freeze

  # Ejecuta el bloque dentro de un contexto de tenancy. Es el ÚNICO sitio que fija el tenant de acts_as_tenant y el
  # `app.organization_id` que leen las políticas RLS (docs/architecture/03-multi-tenancy.md): requests (M0.07), jobs
  # (M0.10), seeds y consola pasan por aquí.
  #
  #   Tenancy.with_context(organization: org, company: co) { |context| Company.count }
  #
  # - Abre una transacción (con savepoint si ya hay una): `SET LOCAL` solo vive dentro de una. Si el bloque lanza, se
  #   revierte lo escrito en él y el setting desaparece con la transacción.
  # - El id se envía como parámetro enlazado (`set_config($1, $2, true)`), nunca interpolado en el SQL.
  # - Al terminar bien, el setting vuelve al valor que tenía (el del contexto externo si estaba anidado), de modo que
  #   no se filtra a lo que siga corriendo en la misma transacción ni en la misma conexión del pool.
  # - Lanza Tenancy::InconsistentContext, sin tocar nada, si las entidades no encajan.
  def self.with_context(organization:, company: nil, branch: nil, principal: nil, &block)
    raise ArgumentError, "with_context requiere un bloque" unless block

    context = Context.new(organization:, company:, branch:, principal:)

    ApplicationRecord.with_connection do |connection|
      connection.transaction(requires_new: true) do
        previous = connection.select_value("SELECT current_setting('#{SETTING}', true)")
        write_setting(connection, organization.id)
        result = ActsAsTenant.with_tenant(organization) { Current.set(context:) { block.call(context) } }
        write_setting(connection, previous.to_s)
        result
      end
    end
  end

  def self.write_setting(connection, value)
    connection.select_value("SELECT set_config($1, $2, true)", "Tenancy.with_context", [ SETTING, value ])
  end
  private_class_method :write_setting
end
