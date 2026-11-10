# Hooks tenancy's write guard into EVERY model that declares acts_as_tenant, without the root pack (ApplicationRecord)
# knowing tenancy: the dependency goes from tenancy to the root pack, not the other way.
#
# Lives in the pack's lib/ (not reloaded) and holds NO reloadable constants: Tenancy::TenantWriteGuard is resolved at call time.
module TenantGuardInstaller
  # Prepended to Base.singleton_class: the gem's acts_as_tenant still runs (super), then the guard is included.
  module ModelMethods
    def acts_as_tenant(*, **)
      super
      include Tenancy::TenantWriteGuard
    end
  end

  # Prepended to ActiveRecord::Relation: bulk writes go through the relation (Model.upsert_all uses it).
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
