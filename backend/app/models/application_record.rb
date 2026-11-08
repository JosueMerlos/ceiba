class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Todo modelo tenant recibe el guard de ESCRITURA (Tenancy::TenantWriteGuard): crear/destruir en otro tenant o
  # mover un registro de organización se rechaza aunque se salten las validaciones. No hay que acordarse de incluirlo.
  def self.acts_as_tenant(*, **)
    super
    include Tenancy::TenantWriteGuard
  end
end
