module Tenancy
  # WRITE barrier of the first tenancy barrier. acts_as_tenant filters reads and validates (but validations can be skipped
  # with `save(validate: false)`); this guard acts in the persistence layer, AFTER all model callbacks, and no save skips it:
  #   - INSERT with an organization_id other than the active tenant's    => TenantMismatch
  #   - UPDATE that writes organization_id (save, update_columns...)     => TenantIsImmutable
  #   - UPDATE/touch/update_columns/DELETE/destroy of an in-memory object from ANOTHER organization (the UPDATE goes by
  #     primary key, without default scope)                              => TenantMismatch, and every statement also carries
  #     `organization_id = <tenant>` in its conditions (defense in depth: it affects 0 rows even if something slips)
  #   - writing without an active tenant                                 => ActsAsTenant::Errors::NoTenantSet
  #   - Model.insert_all/insert_all!/upsert_all with another tenant's rows => TenantMismatch; upsert_all requires `unique_by`
  #     on an index that includes organization_id (otherwise a foreign id would be overwritten and moved tenant);
  #   - Relation#update_all that writes organization_id                  => TenantIsImmutable.
  #
  # WHY in persistence and not `before_save`: callbacks run in declaration order and acts_as_tenant is declared at the top of
  # the model; a later `before_save` changing organization_id would run AFTER the guard and escape. `_insert_record`/
  # `_update_record`/`_delete_record` (class) and `_update_row`/`_delete_row` (instance) run when no callback is left. The
  # tenant_write_guard spec ("canary") fails if a Rails version renames them, so the guard cannot silently stop running.
  #
  # The pack hooks it into every model that declares acts_as_tenant. It does not cover direct-SQL style `update_counters`/
  # `increment!` or raw SQL (`find_by_sql`, `connection.execute`): the last barrier for those is RLS.
  module TenantWriteGuard
    extend ActiveSupport::Concern

    TENANT_COLUMN = "organization_id".freeze

    class_methods do
      def _insert_record(connection, values, returning)
        TenantWriteGuard.ensure_row_in_tenant!(self, values)
        super
      end

      def _update_record(values, constraints)
        TenantWriteGuard.ensure_not_changing_tenant!(self, values)
        super(values, TenantWriteGuard.scoped_constraints(constraints))
      end

      def _delete_record(constraints)
        super(TenantWriteGuard.scoped_constraints(constraints))
      end
    end

    # The checks live here (not in the initializer, which does not reload) so they update with the pack.
    class << self
      def tenant_model?(klass) = klass.include?(TenantWriteGuard)

      def current_tenant!
        ActsAsTenant.current_tenant || raise(ActsAsTenant::Errors::NoTenantSet)
      end

      def ensure_row_in_tenant!(klass, row)
        tenant = current_tenant!
        row = row.to_h.transform_keys(&:to_s)
        return unless row.key?(TENANT_COLUMN)
        value = row[TENANT_COLUMN]
        value = value.value_for_database if value.respond_to?(:value_for_database) # _insert_record receives Attributes
        return if value == tenant.id

        raise TenantMismatch, "#{klass.name}: organization_id #{value.inspect} no es el del tenant activo (#{tenant.id})"
      end

      # Adds organization_id = tenant to the conditions of a primary-key UPDATE/DELETE.
      def scoped_constraints(constraints)
        constraints.to_h.merge(TENANT_COLUMN => current_tenant!.id)
      end

      # Checks the database value, not whatever someone assigned.
      def ensure_record_in_tenant!(record, action)
        return if record.organization_id_in_database == current_tenant!.id

        raise TenantMismatch, "#{record.class.name}: no se puede #{action} un registro de otra organización"
      end

      def ensure_not_changing_tenant!(klass, values)
        current_tenant!
        return unless values.to_h.keys.map(&:to_s).include?(TENANT_COLUMN)

        raise TenantIsImmutable, "#{klass.name}: organization_id no se puede cambiar"
      end

      # insert_all / insert_all! / upsert_all (y insert/insert!/upsert, que delegan en ellos).
      def ensure_bulk_rows!(klass, rows)
        current_tenant!
        Array(rows).each { |row| ensure_row_in_tenant!(klass, row) }
      end

      # A custom (SQL) on_duplicate mentioning organization_id could move rows between organizations.
      def ensure_on_duplicate_safe!(klass, on_duplicate)
        return if on_duplicate.is_a?(Symbol)
        return unless on_duplicate.to_s.match?(/\borganization_id\b/)

        raise ArgumentError, "#{klass.name}.upsert_all: on_duplicate no puede mencionar organization_id"
      end

      def ensure_upsert_target!(klass, unique_by)
        return if unique_columns(klass, unique_by).include?(TENANT_COLUMN)

        raise ArgumentError, "#{klass.name}.upsert_all exige unique_by sobre un índice que incluya organization_id " \
                             "(p. ej. unique_by: %i[organization_id id]); con otro destino un id de otra organización se sobrescribiría"
      end

      def ensure_update_all_allowed!(klass, updates)
        current_tenant!
        touches = case updates
        when Hash then updates.keys.map(&:to_s).include?(TENANT_COLUMN)
        else updates.to_s.match?(/\borganization_id\b/)
        end
        raise TenantIsImmutable, "#{klass.name}: update_all no puede escribir organization_id" if touches
      end

      private

      def unique_columns(klass, unique_by)
        return [] if unique_by.nil?
        return Array(unique_by).map(&:to_s) if unique_by.is_a?(Array)

        index = klass.with_connection { |connection| connection.indexes(klass.table_name).find { |candidate| candidate.name == unique_by.to_s } }
        index ? Array(index.columns).map(&:to_s) : [ unique_by.to_s ]
      end
    end

    included do
      before_destroy :ensure_destroy_in_tenant
    end

    # update_columns/update_column bypass _update_row, so check here with a clear message.
    def update_columns(attributes)
      TenantWriteGuard.ensure_not_changing_tenant!(self.class, attributes)
      TenantWriteGuard.ensure_record_in_tenant!(self, "actualizar")
      super
    end

    private

    # Used by update/update!/update_attribute/touch (_update_row) and delete (_delete_row).
    def _update_row(attribute_names, attempted_action = "update")
      TenantWriteGuard.ensure_record_in_tenant!(self, attempted_action == "touch" ? "tocar" : "actualizar")
      super
    end

    def _delete_row
      TenantWriteGuard.ensure_record_in_tenant!(self, "borrar")
      super
    end

    def ensure_destroy_in_tenant
      TenantWriteGuard.ensure_record_in_tenant!(self, "destruir")
    end
  end
end
