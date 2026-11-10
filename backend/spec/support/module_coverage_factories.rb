# Cómo fabricar un RECURSO REAL para cada parámetro de ruta de un módulo (:id, :service_id...) en la suite de cobertura de módulos
# (spec/requests/api/module_coverage_spec.rb). Con un id desconocido la ruta daría 404 por sí sola y la suite no probaría que el 404
# lo emite el gate; por eso cada módulo con rutas de miembro REGISTRA aquí cómo conseguir un id existente en la empresa dada.
# :organization_id, :company_id y :branch_id los resuelve la suite sola (sucursal real de la empresa).
#
#   ModuleCoverageFactories.register("appointments", :id) { |company:, branch:| create_in(company.organization, :appointment, ...).id }
#
# Si un módulo tiene una ruta con un parámetro sin fabricante, la suite FALLA diciendo cuál registrar (nunca lo salta).
module ModuleCoverageFactories
  class Missing < StandardError; end

  FACTORIES = {}

  module_function

  def register(module_key, param, &block) = FACTORIES[[ module_key.to_s, param.to_sym ]] = block

  def build(module_key, param, company:, branch:)
    factory = FACTORIES[[ module_key.to_s, param.to_sym ]] or
      raise Missing, "registra un fabricante para :#{param} de #{module_key} (ModuleCoverageFactories.register en spec/support)"
    factory.call(company:, branch:)
  end
end

# sample: sus "cosas" son las sucursales de la empresa.
ModuleCoverageFactories.register("sample", :id) { |branch:, **| branch.id }
