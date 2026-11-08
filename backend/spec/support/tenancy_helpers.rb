# Helpers de specs para trabajar dentro de un tenant. Un spec que toca modelos tenant sin contexto falla por
# diseño (acts_as_tenant require_tenant): este helper es la forma corta de abrir uno.
module TenancyHelpers
  def with_tenant(organization, &)
    Tenancy.with_context(organization:, &)
  end

  # create_in(org, :company, name: "X") == with_tenant(org) { create(:company, name: "X") }
  def create_in(organization, *, **, &)
    with_tenant(organization) { create(*, **, &) }
  end

  # Una sentencia que falla en PostgreSQL aborta la transacción que la contiene; dentro de with_tenant (que ya es una
  # transacción) hay que aislar el intento en un savepoint para poder afirmar el error y seguir.
  def savepoint(&)
    ApplicationRecord.transaction(requires_new: true, &)
  end

  def new_organization(name = "Organización #{SecureRandom.hex(3)}")
    Tenancy::Organization.create!(name:)
  end
end

RSpec.configure { |config| config.include TenancyHelpers }
