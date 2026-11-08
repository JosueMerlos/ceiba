# Helpers de specs para trabajar dentro de un tenant. Un spec que toca modelos tenant sin contexto falla por
# diseño (acts_as_tenant require_tenant): este helper es la forma corta de abrir uno.
module TenancyHelpers
  def with_tenant(organization, &block)
    ActsAsTenant.with_tenant(organization, &block)
  end

  def new_organization(name = "Organización #{SecureRandom.hex(3)}")
    Tenancy::Organization.create!(name:)
  end
end

RSpec.configure { |config| config.include TenancyHelpers }
