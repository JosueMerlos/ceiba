# Helpers de specs para trabajar dentro de un tenant. Un spec que toca modelos tenant sin contexto falla por
# diseño (acts_as_tenant require_tenant): este helper es la forma corta de abrir uno.
module TenancyHelpers
  def with_tenant(organization, &)
    Tenancy.with_context(organization:, &)
  end

  # create_in(org, :company, name: "X") == with_tenant(org) { create(:company, name: "X") }
  def create_in(organization, *, **, &)
    with_tenant(organization) { create(*, **, &) }
  end

  # Una sentencia que falla en PostgreSQL aborta la transacción que la contiene; dentro de with_tenant (que ya es una
  # transacción) hay que aislar el intento en un savepoint para poder afirmar el error y seguir.
  def savepoint(&)
    ApplicationRecord.transaction(requires_new: true, &)
  end

  # Para specs SIN fixtures transaccionales (COMMIT real): borra todo lo que las organizaciones dejaron en CUALQUIER tabla
  # tenant (empresas, sucursales, eventos del outbox...) y luego las organizaciones. Tolera el orden de las FKs repitiendo
  # pasadas: una tabla que aún tiene hijos (RESTRICT) se reintenta en la pasada siguiente.
  def purge_organizations(organizations)
    ids = Array(organizations).map { |organization| organization.respond_to?(:id) ? organization.id : organization }
    return if ids.empty?

    purge_append_only_rows(ids)
    pending = Database::TenantTables.names - TenantIsolation::APPEND_ONLY_TABLES
    pending.size.times do
      pending = pending.reject do |table|
        savepoint { ApplicationRecord.connection.delete("DELETE FROM #{ApplicationRecord.connection.quote_table_name(table)} WHERE organization_id IN (#{ids.map { |id| ApplicationRecord.connection.quote(id) }.join(',')})") }
        true
      rescue ActiveRecord::StatementInvalid
        false
      end
      break if pending.empty?
    end
    Tenancy::Organization.where(id: ids).delete_all
  end

  # Las tablas append-only (audit_events) rechazan el DELETE del rol de la aplicación por diseño. Un spec con COMMIT real
  # que audita deja filas que bloquearían el borrado de la organización (FK RESTRICT): las limpia el DUEÑO, desactivando
  # el trigger solo dentro de su transacción (control contra la aplicación, no contra el dueño; docs/architecture/11).
  def purge_append_only_rows(ids)
    OwnerConnection.with do |owner|
      owner.transaction do
        TenantIsolation::APPEND_ONLY_TABLES.each do |table|
          owner.execute("ALTER TABLE #{table} DISABLE TRIGGER USER")
          owner.execute("DELETE FROM #{table} WHERE organization_id IN (#{ids.map { |id| owner.quote(id) }.join(',')})")
          owner.execute("ALTER TABLE #{table} ENABLE TRIGGER USER")
        end
      end
    end
  end

  def new_organization(name = "Organización #{SecureRandom.hex(3)}")
    Tenancy::Organization.create!(name:)
  end
end

RSpec.configure { |config| config.include TenancyHelpers }
