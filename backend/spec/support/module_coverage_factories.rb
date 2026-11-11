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

# appointments: :id is a service of the company; :service_id is a service WITH an override in the branch, so the override
# routes find a real row (an absent override is a 404 of its own, not of the gate).
ModuleCoverageFactories.register("appointments", :id) do |company:, **|
  Tenancy.with_context(organization: company.organization) { FactoryBot.create(:service, company:).id }
end
ModuleCoverageFactories.register("appointments", :service_id) do |company:, branch:|
  Tenancy.with_context(organization: company.organization) do
    service = FactoryBot.create(:service, company:)
    FactoryBot.create(:branch_service_override, service:, branch:)
    service.id
  end
end

# The owners the branch routes name. Find-or-create, so every route of one run sees the SAME professional (assigned to the
# suite's branch: the branch routes need the assignment to answer by themselves) and the SAME resource (of that branch); the
# absence builders create the absence of THAT same owner (an absence of another owner would be a 404 on a DELETE, even with
# the module active). An archived one (the suite visits the DELETE routes) is replaced by a fresh one. Call inside Tenancy.with_context.
module AppointmentsCoverageOwners
  module_function

  def professional(company:, branch:)
    professional = Appointments::Professional.unarchived.find_by(company_id: company.id, display_name: "Cobertura") ||
                   FactoryBot.create(:professional, company:, display_name: "Cobertura")
    FactoryBot.create(:professional_branch_assignment, professional:, branch:) unless
      Appointments::ProfessionalBranchAssignment.exists?(professional_id: professional.id, branch_id: branch.id)
    professional
  end

  def resource(branch:)
    Appointments::Resource.unarchived.find_by(branch_id: branch.id, name: "Cobertura") || FactoryBot.create(:resource, branch:, name: "Cobertura")
  end
end

ModuleCoverageFactories.register("appointments", :professional_id) do |company:, branch:|
  Tenancy.with_context(organization: company.organization) { AppointmentsCoverageOwners.professional(company:, branch:).id }
end
ModuleCoverageFactories.register("appointments", :resource_id) do |branch:, company:|
  Tenancy.with_context(organization: company.organization) { AppointmentsCoverageOwners.resource(branch:).id }
end
ModuleCoverageFactories.register("appointments", :professional_time_off_id) do |company:, branch:|
  Tenancy.with_context(organization: company.organization) do
    FactoryBot.create(:time_off, professional: AppointmentsCoverageOwners.professional(company:, branch:)).id
  end
end
ModuleCoverageFactories.register("appointments", :resource_time_off_id) do |company:, branch:|
  Tenancy.with_context(organization: company.organization) { FactoryBot.create(:time_off, resource: AppointmentsCoverageOwners.resource(branch:)).id }
end
