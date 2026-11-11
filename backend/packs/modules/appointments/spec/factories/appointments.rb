FactoryBot.define do
  # Used INSIDE a tenant. Services and overrides store only ids (no association to the private Tenancy models), so the
  # company (and the branch) are transients: organization_id, company_id and the currency always come from them.
  factory :service, class: "Appointments::Service" do
    transient { company { association(:company, strategy: :create) } }

    company_id { company.id }
    organization { company.organization }
    currency { company.currency }
    sequence(:name) { |n| "Servicio #{n}" }
    duration_minutes { 30 }
    price_minor { 20_000 }
  end

  # The override's company and organization come from its service; the branch must belong to that company.
  factory :branch_service_override, class: "Appointments::BranchServiceOverride" do
    transient do
      service { association(:service, strategy: :create) }
      branch { association(:branch, company: Tenancy::Directory.company!(service.company_id), strategy: :create) }
    end

    service_id { service.id }
    branch_id { branch.id }
    company_id { service.company_id }
    organization { service.organization }
    duration_minutes { 45 }
  end
end
