FactoryBot.define do
  factory :organization, class: "Tenancy::Organization" do
    sequence(:name) { |n| "Organización #{n}" }
  end

  # Una empresa se crea en el tenant activo; fuera de un tenant crea su propia organización. En ambos casos se guarda
  # dentro del tenant de SU organización (to_create): las factories son datos de prueba del tenant que declaran, no
  # un bypass; la lectura posterior sigue necesitando un contexto.
  factory :company, class: "Tenancy::Company" do
    organization { ActsAsTenant.current_tenant || association(:organization) }
    sequence(:name) { |n| "Empresa #{n}" }
    sequence(:slug) { |n| "empresa-#{n}" }
    business_type { "salon" }
    currency { "NIO" }

    to_create { |company| ActsAsTenant.with_tenant(company.organization) { company.save! } }
  end

  # organization_id sale de la EMPRESA, nunca se genera aparte: la FK compuesta lo exige.
  factory :branch, class: "Tenancy::Branch" do
    company
    organization { company.organization }
    sequence(:name) { |n| "Sucursal #{n}" }
    time_zone { "America/Managua" }

    to_create { |branch| ActsAsTenant.with_tenant(branch.organization) { branch.save! } }
  end
end
