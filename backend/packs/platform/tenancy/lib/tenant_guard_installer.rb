# Engancha el guard de escritura de tenancy en TODO modelo que declare acts_as_tenant, sin que el pack raíz
# (ApplicationRecord) conozca a tenancy: la dependencia va de tenancy hacia el pack raíz, no al revés.
#
# Vive en lib/ del pack (no se recarga) y NO guarda constantes recargables: Tenancy::TenantWriteGuard se resuelve en
# el momento de la llamada.
module TenantGuardInstaller
  # Se antepone a Base.singleton_class: acts_as_tenant sigue siendo el de la gema (super) y luego se incluye el guard.
  module ModelMethods
    def acts_as_tenant(*, **)
      super
      include Tenancy::TenantWriteGuard
    end
  end

  # Se antepone a ActiveRecord::Relation: las escrituras masivas pasan por la relación (Model.upsert_all la usa).
  module RelationMethods
    def insert_all(attributes, **)
      guard! { |guard| guard.ensure_bulk_rows!(klass, attributes) }
      super
    end

    def insert_all!(attributes, **)
      guard! { |guard| guard.ensure_bulk_rows!(klass, attributes) }
      super
    end

    def upsert_all(attributes, unique_by: nil, on_duplicate: :update, **options)
      guard! do |guard|
        guard.ensure_upsert_target!(klass, unique_by)
        guard.ensure_on_duplicate_safe!(klass, on_duplicate)
        guard.ensure_bulk_rows!(klass, attributes)
      end
      super(attributes, unique_by:, on_duplicate:, **options)
    end

    def update_all(updates)
      guard! { |guard| guard.ensure_update_all_allowed!(klass, updates) }
      super
    end

    private

    def guard!
      guard = Tenancy::TenantWriteGuard
      yield guard if guard.tenant_model?(klass)
    end
  end

  def self.install!
    ActiveRecord::Base.singleton_class.prepend(ModelMethods)
    ActiveRecord::Relation.prepend(RelationMethods)
  end
end
