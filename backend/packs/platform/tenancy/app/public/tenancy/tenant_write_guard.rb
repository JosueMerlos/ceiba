module Tenancy
  # Barrera de ESCRITURA de la barrera 1 (docs/architecture/03-multi-tenancy.md). acts_as_tenant filtra lecturas y valida
  # (pero las validaciones se pueden saltar con `save(validate: false)`); este guard actúa en before_save/before_destroy,
  # que no se saltan:
  #   - crear o destruir un registro con organization_id distinto del tenant activo => TenantMismatch;
  #   - cambiar el organization_id de un registro existente => TenantIsImmutable;
  #   - escribir sin tenant activo => ActsAsTenant::Errors::NoTenantSet.
  # Se incluye solo: ApplicationRecord.acts_as_tenant lo añade a todo modelo tenant, y la suite de aislamiento lo exige.
  # Lo que no pasa por callbacks (update_columns, update_all, SQL crudo) lo cierra RLS en M4.03.
  module TenantWriteGuard
    extend ActiveSupport::Concern

    included do
      before_save :ensure_tenant_write_allowed
      before_destroy :ensure_destroy_in_tenant
    end

    private

    def ensure_tenant_write_allowed
      tenant = current_tenant!
      raise TenantIsImmutable, "#{self.class.name}: organization_id no se puede cambiar" if persisted? && organization_id_changed?
      return if organization_id == tenant.id

      raise TenantMismatch, "#{self.class.name}: organization_id #{organization_id.inspect} no es el del tenant activo (#{tenant.id})"
    end

    def ensure_destroy_in_tenant
      tenant = current_tenant!
      return if organization_id == tenant.id

      raise TenantMismatch, "#{self.class.name}: no se puede destruir un registro de otra organización"
    end

    def current_tenant!
      ActsAsTenant.current_tenant || raise(ActsAsTenant::Errors::NoTenantSet)
    end
  end
end
