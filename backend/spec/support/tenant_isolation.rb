# Discovery and checks for the tenant isolation suite.
#
# A model is "tenant" if its table has an organization_id column: discovery is based on the SCHEMA, not a manual list,
# so a new model in any pack is covered without writing a new test. Complements the platform/database guardian (tables
# with organization_id == tables with a tenant_isolation policy).
module TenantIsolation
  # table => reason. Tenant tables without an ActiveRecord model (e.g. a join table), hence not coverable here.
  # Empty: every tenant table has a model. An exemption needs a written reason and review.
  UNMODELED_TABLES = {}.freeze

  # INSERT-ONLY tables (append-only trigger): no row is ever updated or deleted, not even its own, so the examples that
  # test foreign writes (UPDATE/DELETE) do not apply; the read and INSERT isolation ones do.
  APPEND_ONLY_TABLES = %w[audit_events].freeze

  class MissingFactory < StandardError; end

  module_function

  # Tenant models of the application (or of `candidates`), sorted by name.
  def models(candidates = nil)
    Rails.application.eager_load! if candidates.nil?
    (candidates || ApplicationRecord.descendants).select { |model| tenant_model?(model) }.sort_by(&:name)
  end

  def append_only?(model) = APPEND_ONLY_TABLES.include?(model.table_name)

  def tenant_model?(model)
    return false if model.abstract_class? || model.name.blank? || !model.name.safe_constantize.equal?(model)

    model.table_exists? && model.column_names.include?("organization_id")
  end

  # The factory registered for the model (the one that builds that model), or nil.
  def factory_for(model)
    FactoryBot.factories.to_a.find { |factory| build_class(factory) == model }
  end

  def factory_for!(model)
    factory_for(model) || raise(MissingFactory, missing_factory_message(model))
  end

  def missing_factories(models)
    models.reject { |model| factory_for(model) }
  end

  # Tenant tables (with a tenant_isolation policy) that no discovered model covers and are not exempt.
  def uncovered_tables(models)
    Database::TenantTables.names - models.map(&:table_name) - UNMODELED_TABLES.keys.map(&:to_s)
  end

  # Associations that would cross tenants. acts_as_tenant's default scope filters the model's QUERY, but an association
  # whose condition is `organization_id = <another record's>` REPLACES that condition: from an organization loaded in
  # context A, `organization.companies` would return B's. Forbidden:
  #   - any association FROM a root model (no organization_id) TO a tenant model;
  #   - any association to a tenant model whose foreign key is organization_id.
  # Children relate to their tenant parent through the parent's key (company_id), within the active tenant.
  def association_violations(models = nil)
    Rails.application.eager_load! if models.nil?
    candidates = models || ApplicationRecord.descendants.select { |model| named?(model) && !model.abstract_class? }
    candidates.flat_map do |model|
      model.reflect_on_all_associations.filter_map do |reflection|
        target = target_of(reflection)
        next unless target && tenant_model?(target)
        next unless !tenant_model?(model) || Array(reflection.foreign_key).map(&:to_s).include?("organization_id")

        "#{model.name}.#{reflection.macro} :#{reflection.name} -> #{target.name} (foreign_key #{Array(reflection.foreign_key).join(',')}): " \
          "cruzaría tenants; consulta #{target.name} dentro de un tenant en vez de declarar la asociación"
      end
    end
  end

  def target_of(reflection)
    reflection.polymorphic? ? nil : reflection.klass
  rescue NameError
    nil
  end

  def named?(model) = model.name.present? && model.name.safe_constantize.equal?(model)

  def missing_factory_message(model)
    "Falta una factory para #{model.name} (tabla #{model.table_name}, con organization_id): agrega " \
      "`factory :#{model.name.demodulize.underscore}, class: \"#{model.name}\"` en spec/factories o en packs/*/*/spec/factories. " \
      "Sin ella la suite de aislamiento no puede demostrar que #{model.name} no filtra datos entre organizaciones. " \
      "La factory debe derivar organization_id del padre o del tenant activo, nunca generarlo por separado."
  end

  def build_class(factory)
    factory.build_class
  rescue NameError
    nil
  end
end
