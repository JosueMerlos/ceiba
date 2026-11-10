# Public API of the platform/tenancy pack (together with Tenancy::Context, Tenancy::ProvisionOrganization and the errors).
module Tenancy
  SETTING = "app.organization_id".freeze

  # Runs the block inside a tenancy context. It is the ONLY place that sets acts_as_tenant's tenant and the
  # `app.organization_id` the RLS policies read: requests, jobs, seeds and the console all go through here.
  #
  #   Tenancy.with_context(organization: org, company: co) { |context| Company.count }
  #
  # - Opens a transaction (a savepoint if one exists): `SET LOCAL` only lives inside one. If the block raises, what it wrote
  #   rolls back and the setting vanishes with the transaction.
  # - The id is sent as a bound parameter (`set_config($1, $2, true)`), never interpolated into SQL.
  # - On success the setting returns to its previous value (the outer context's when nested), so it does not leak to what
  #   runs next in the same transaction or pooled connection.
  # - `read_only: true` (API reads, GET) makes the transaction READ ONLY (`SET TRANSACTION READ ONLY`): an accidental write
  #   fails in the database and a read's long transaction is cheaper. Only the OUTERMOST context sets it (a foreign
  #   transaction, e.g. test fixtures or a job, does not change mode); a nested context inherits it.
  # - Raises Tenancy::InconsistentContext, touching nothing, if the entities do not fit.
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

  # Restores the setting on non-local exits too (return, break, throw): the savepoint is released and the setting does NOT
  # revert on its own. On an exception it is NOT restored: the savepoint rollback already reverts it, and on an aborted
  # transaction any statement would fail and mask the original error.
  def self.run_in_context(connection, organization, context, previous, &block)
    failed = false
    ActsAsTenant.with_tenant(organization) { Current.set(context:) { block.call(context) } }
  rescue Exception # rubocop:disable Lint/RescueException -- always re-raised; only flags that no restore is needed
    failed = true
    raise
  ensure
    write_setting(connection, previous.to_s) unless failed
  end
  private_class_method :run_in_context

  # No query cache: Rails enables it in requests and jobs, and a set_config served from the cache would not run.
  def self.read_setting(connection)
    connection.uncached { connection.select_value("SELECT current_setting('#{SETTING}', true)") }
  end
  private_class_method :read_setting

  def self.write_setting(connection, value)
    connection.uncached { connection.select_value("SELECT set_config($1, $2, true)", "Tenancy.with_context", [ SETTING, value ]) }
  end
  private_class_method :write_setting
end
