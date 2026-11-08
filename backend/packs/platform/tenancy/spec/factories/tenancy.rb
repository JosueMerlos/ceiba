FactoryBot.define do
  factory :organization, class: "Tenancy::Organization" do
    sequence(:name) { |n| "Organización #{n}" }
  end

  # Las factories tenant se usan DENTRO de un tenant (`with_tenant(org) { create(:company) }` o `create_in(org, :company)`):
  # construir un modelo tenant sin tenant falla por diseño, y una factory no es un bypass. La organización de una
  # empresa es la del tenant activo.
  factory :company, class: "Tenancy::Company" do
    organization { ActsAsTenant.current_tenant }
    sequence(:name) { |n| "Empresa #{n}" }
    sequence(:slug) { |n| "empresa-#{n}" }
    business_type { "salon" }
    currency { "NIO" }
  end

  # organization_id sale de la EMPRESA, nunca se genera aparte: la FK compuesta lo exige.
  factory :branch, class: "Tenancy::Branch" do
    company
    organization { company.organization }
    sequence(:name) { |n| "Sucursal #{n}" }
    time_zone { "America/Managua" }
  end
end
