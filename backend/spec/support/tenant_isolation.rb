# Descubrimiento y comprobaciones de la suite de aislamiento de tenant (docs/architecture/12-testing-strategy.md).
#
# Un modelo es "tenant" si su tabla tiene la columna organization_id: el descubrimiento se basa en el ESQUEMA, no en
# una lista manual, así un modelo nuevo de cualquier pack queda cubierto sin escribir un test nuevo. Complementa al
# guardián de platform/database (tablas con organization_id == tablas con política tenant_isolation).
module TenantIsolation
  # tabla => motivo. Tablas tenant sin modelo de ActiveRecord (p. ej. una tabla puente) y por tanto no cubribles aquí.
  # Vacío: toda tabla tenant tiene modelo. Una exención exige un motivo escrito y revisión.
  UNMODELED_TABLES = {}.freeze

  class MissingFactory < StandardError; end

  module_function

  # Modelos tenant de la aplicación (o de `candidates`), ordenados por nombre.
  def models(candidates = nil)
    Rails.application.eager_load! if candidates.nil?
    (candidates || ApplicationRecord.descendants).select { |model| tenant_model?(model) }.sort_by(&:name)
  end

  def tenant_model?(model)
    return false if model.abstract_class? || model.name.blank? || !model.name.safe_constantize.equal?(model)

    model.table_exists? && model.column_names.include?("organization_id")
  end

  # La factory registrada para el modelo (la que construye ese modelo), o nil.
  def factory_for(model)
    FactoryBot.factories.to_a.find { |factory| build_class(factory) == model }
  end

  def factory_for!(model)
    factory_for(model) || raise(MissingFactory, missing_factory_message(model))
  end

  def missing_factories(models)
    models.reject { |model| factory_for(model) }
  end

  # Tablas tenant (con política tenant_isolation) que ningún modelo descubierto cubre y no están exentas.
  def uncovered_tables(models)
    Database::TenantTables.names - models.map(&:table_name) - UNMODELED_TABLES.keys.map(&:to_s)
  end

  # Asociaciones que cruzarían tenants. El default scope de acts_as_tenant filtra la CONSULTA del modelo, pero una
  # asociación cuya condición es `organization_id = <el de otro registro>` REEMPLAZA esa condición: desde una
  # organización cargada en el contexto A, `organization.companies` devolvería las de B. Se prohíbe:
  #   - cualquier asociación DESDE un modelo raíz (sin organization_id) HACIA un modelo tenant;
  #   - cualquier asociación hacia un modelo tenant cuya clave foránea sea organization_id.
  # Los hijos se relacionan con su padre tenant por la clave del padre (company_id), dentro del tenant activo.
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
