# Spec helpers for working inside a tenant. A spec that touches tenant models without a context fails by design
# (acts_as_tenant require_tenant): this helper is the short way to open one.
module TenancyHelpers
  def with_tenant(organization, &)
    Tenancy.with_context(organization:, &)
  end

  # create_in(org, :company, name: "X") == with_tenant(org) { create(:company, name: "X") }
  def create_in(organization, *, **, &)
    with_tenant(organization) { create(*, **, &) }
  end

  # A statement that fails in PostgreSQL aborts the transaction containing it; inside with_tenant (already a
  # transaction) the attempt must be isolated in a savepoint to assert the error and carry on.
  def savepoint(&)
    ApplicationRecord.transaction(requires_new: true, &)
  end

  # For specs WITHOUT transactional fixtures (real COMMIT): deletes everything the organizations left in ANY tenant
  # table (companies, branches, outbox events...) and then the organizations. Tolerates FK order by repeating passes: a
  # table that still has children (RESTRICT) is retried on the next pass.
  def purge_organizations(organizations, user_ids: [])
    ids = Array(organizations).map { |organization| organization.respond_to?(:id) ? organization.id : organization }
    return if ids.empty?

    purge_append_only_rows(ids, user_ids)
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

  # Append-only tables (audit_events) reject the application role's DELETE by design. A real-COMMIT spec that audits
  # leaves rows that would block deleting the organization (FK RESTRICT): the OWNER cleans them, disabling the trigger
  # only inside its transaction (a control against the application, not against the owner).
  def purge_append_only_rows(ids, user_ids = [])
    OwnerConnection.with do |owner|
      owner.transaction do
        TenantIsolation::APPEND_ONLY_TABLES.each do |table|
          owner.execute("ALTER TABLE #{table} DISABLE TRIGGER USER")
          owner.execute("DELETE FROM #{table} WHERE organization_id IN (#{ids.map { |id| owner.quote(id) }.join(',')})")
          owner.execute("ALTER TABLE #{table} ENABLE TRIGGER USER")
        end
        purge_auth_audit_events(owner, user_ids)
      end
    end
  end

  # auth_audit_events (global, no organization): the rows of the users the spec created are cleaned.
  def purge_auth_audit_events(owner, user_ids)
    return if user_ids.empty?

    owner.execute("ALTER TABLE auth_audit_events DISABLE TRIGGER USER")
    owner.execute("DELETE FROM auth_audit_events WHERE user_id IN (#{user_ids.map { |id| owner.quote(id) }.join(',')})")
    owner.execute("ALTER TABLE auth_audit_events ENABLE TRIGGER USER")
  end

  def new_organization(name = "Organización #{SecureRandom.hex(3)}")
    Tenancy::Organization.create!(name:)
  end
end

RSpec.configure { |config| config.include TenancyHelpers }
