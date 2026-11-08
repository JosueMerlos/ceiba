module Tenancy
  # Barrera de ESCRITURA de la barrera 1 (docs/architecture/03-multi-tenancy.md). acts_as_tenant filtra lecturas y valida
  # (pero las validaciones se pueden saltar con `save(validate: false)`); este guard actúa en la capa de persistencia,
  # DESPUÉS de todos los callbacks del modelo, y no se salta con ningún save:
  #   - INSERT con organization_id distinto del tenant activo        => TenantMismatch
  #   - UPDATE que escribe organization_id (save, update_columns...) => TenantIsImmutable
  #   - DELETE/destroy de un registro de otra organización           => TenantMismatch
  #   - escribir sin tenant activo                                   => ActsAsTenant::Errors::NoTenantSet
  #   - Model.insert_all/insert_all!/upsert_all con filas de otro tenant => TenantMismatch; upsert_all exige `unique_by`
  #     sobre un índice que incluya organization_id (si no, un id ajeno se sobrescribiría y se movería de tenant);
  #   - Relation#update_all que escribe organization_id => TenantIsImmutable.
  #
  # POR QUÉ en persistencia y no en `before_save`: los callbacks corren en el orden en que se declaran y acts_as_tenant se
  # declara arriba del modelo; un `before_save` posterior que cambiara organization_id llegaría DESPUÉS del guard y
  # escaparía. `_insert_record`/`_update_record`/`_delete_row` se ejecutan cuando ya no queda ningún callback.
  #
  # Lo engancha el pack (config/initializers/tenant_write_guard.rb) en todo modelo que declara acts_as_tenant.
  # No cubre `touch`, `delete`/`update_counters` sobre objetos ajenos ni SQL crudo: el default scope los acota al tenant
  # y la última barrera es RLS (M4.03).
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
        super
      end
    end

    # Las comprobaciones viven aquí (y no en el initializer, que no se recarga) para que se actualicen con el pack.
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
        value = value.value_for_database if value.respond_to?(:value_for_database) # _insert_record recibe Attributes
        return if value == tenant.id

        raise TenantMismatch, "#{klass.name}: organization_id #{value.inspect} no es el del tenant activo (#{tenant.id})"
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

    # update_columns/update_column pasan por _update_record, pero se corta antes con un mensaje claro.
    def update_columns(attributes)
      TenantWriteGuard.ensure_not_changing_tenant!(self.class, attributes)
      super
    end

    private

    def ensure_destroy_in_tenant
      return if organization_id == TenantWriteGuard.current_tenant!.id

      raise TenantMismatch, "#{self.class.name}: no se puede destruir un registro de otra organización"
    end
  end
end
