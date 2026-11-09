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
  # - `read_only: true` (las lecturas de la API, GET) hace la transacción de SOLO LECTURA (`SET TRANSACTION READ ONLY`): una
  #   escritura accidental falla en la base y la transacción larga de una lectura es más barata. Solo lo fija el contexto MÁS
  #   EXTERNO (una transacción ajena —fixtures de test, un job— no cambia de modo); un contexto anidado lo hereda.
  # - Lanza Tenancy::InconsistentContext, sin tocar nada, si las entidades no encajan.
  def self.with_context(organization:, company: nil, branch: nil, principal: nil, read_only: false, &block)
    raise ArgumentError, "with_context requiere un bloque" unless block

    context = Context.new(organization:, company:, branch:, principal:)

    ApplicationRecord.with_connection do |connection|
      connection.transaction(requires_new: true) do
        connection.execute("SET TRANSACTION READ ONLY") if read_only && connection.open_transactions == 1
        previous = read_setting(connection)
        write_setting(connection, organization.id)
        run_in_context(connection, organization, context, previous, &block)
      end
    end
  end

  # Restaura el setting también en una salida no local (return, break, throw): el savepoint se libera y el setting NO
  # se revierte solo. Con una excepción NO se restaura: el rollback del savepoint ya lo revierte, y sobre una
  # transacción abortada cualquier sentencia fallaría y taparía el error original.
  def self.run_in_context(connection, organization, context, previous, &block)
    failed = false
    ActsAsTenant.with_tenant(organization) { Current.set(context:) { block.call(context) } }
  rescue Exception # rubocop:disable Lint/RescueException -- se re-lanza siempre; solo marca que no hay que restaurar
    failed = true
    raise
  ensure
    write_setting(connection, previous.to_s) unless failed
  end
  private_class_method :run_in_context

  # SIN query cache: Rails la activa en requests y jobs, y un set_config servido desde la caché no se ejecutaría.
  def self.read_setting(connection)
    connection.uncached { connection.select_value("SELECT current_setting('#{SETTING}', true)") }
  end
  private_class_method :read_setting

  def self.write_setting(connection, value)
    connection.uncached { connection.select_value("SELECT set_config($1, $2, true)", "Tenancy.with_context", [ SETTING, value ]) }
  end
  private_class_method :write_setting
end
