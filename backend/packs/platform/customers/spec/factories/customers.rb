FactoryBot.define do
  # Like the tenancy factories, used INSIDE a tenant. The customer stores only company_id (no association to the private
  # Tenancy::Company), so the company is a transient and organization_id always comes from it.
  factory :customer, class: "Customers::Customer" do
    transient { company { association(:company, strategy: :create) } }

    company_id { company.id }
    organization { company.organization }
    sequence(:full_name) { |n| "Cliente #{n}" }
    sequence(:phone_e164) { |n| format("+5058800%04d", n) }
  end
end
