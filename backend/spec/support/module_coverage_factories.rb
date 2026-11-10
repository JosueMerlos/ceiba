# How to build a REAL RESOURCE for each of a module's route parameters (:id, :service_id...) in the module coverage suite.
# With an unknown id the route would give 404 by itself and the suite would not prove the gate emits the 404; so every
# module with member routes REGISTERS here how to get an id that exists in the given company.
# The suite resolves :organization_id, :company_id and :branch_id itself (a real branch of the company).
#
#   ModuleCoverageFactories.register("appointments", :id) { |company:, branch:| create_in(company.organization, :appointment, ...).id }
#
# If a module has a route with a parameter that has no builder, the suite FAILS saying which one to register (never skips it).
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

# sample: its "things" are the company's branches.
ModuleCoverageFactories.register("sample", :id) { |branch:, **| branch.id }
