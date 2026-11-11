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

# A professional of a company; the person (user_id) is optional. Organization and company come from the transient company.
FactoryBot.define do
  factory :professional, class: "Appointments::Professional" do
    transient { company { association(:company, strategy: :create) } }

    company_id { company.id }
    organization { company.organization }
    sequence(:display_name) { |n| "Profesional #{n}" }
  end

  # The assignment's company and organization come from its professional; the branch must belong to that company.
  factory :professional_branch_assignment, class: "Appointments::ProfessionalBranchAssignment" do
    transient do
      professional { association(:professional, strategy: :create) }
      branch { association(:branch, company: Tenancy::Directory.company!(professional.company_id), strategy: :create) }
    end

    professional_id { professional.id }
    branch_id { branch.id }
    company_id { professional.company_id }
    organization { professional.organization }
  end

  # The service must belong to the professional's company.
  factory :professional_service, class: "Appointments::ProfessionalService" do
    transient do
      professional { association(:professional, strategy: :create) }
      service { association(:service, company: Tenancy::Directory.company!(professional.company_id), strategy: :create) }
    end

    professional_id { professional.id }
    service_id { service.id }
    company_id { professional.company_id }
    organization { professional.organization }
  end
end

# A physical resource of one branch; the company and organization come from the branch.
FactoryBot.define do
  factory :resource, class: "Appointments::Resource" do
    transient { branch { association(:branch, strategy: :create) } }

    branch_id { branch.id }
    company_id { branch.company_id }
    organization { branch.organization }
    sequence(:name) { |n| "Sillón #{n}" }
    kind { "chair" }
  end

  # The kind of resource a service needs; the company and organization come from the service.
  factory :service_resource_requirement, class: "Appointments::ServiceResourceRequirement" do
    transient { service { association(:service, strategy: :create) } }

    service_id { service.id }
    company_id { service.company_id }
    organization { service.organization }
    kind { "chair" }
  end

  # Weekly hours of a branch, or of a professional or a resource at that branch (pass `professional:` or `resource:`). The
  # professional must be assigned to the branch for the row to exist.
  factory :weekly_schedule, class: "Appointments::WeeklySchedule" do
    transient do
      branch { association(:branch, strategy: :create) }
      professional { nil }
      resource { nil }
    end

    branch_id { branch.id }
    company_id { branch.company_id }
    organization { branch.organization }
    owner_type { professional ? "professional" : (resource ? "resource" : "branch") }
    professional_id { professional&.id }
    resource_id { resource&.id }
    weekday { 1 }
    starts_at_local { "09:00" }
    ends_at_local { "13:00" }
  end

  # An absence of a professional (a new one by default) or of a resource (pass `resource:`).
  factory :time_off, class: "Appointments::TimeOff" do
    transient do
      resource { nil }
      professional { resource ? nil : association(:professional, strategy: :create) }
    end

    owner_type { professional ? "professional" : "resource" }
    professional_id { professional&.id }
    resource_id { resource&.id }
    company_id { (professional || resource).company_id }
    organization { (professional || resource).organization }
    starts_at { Time.utc(2026, 11, 16, 9) }
    ends_at { Time.utc(2026, 11, 16, 13) }
  end
end
