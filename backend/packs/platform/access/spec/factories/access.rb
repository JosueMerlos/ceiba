FactoryBot.define do
  # Non-system test role, to test coverage semantics with a single permission without relying on the seeded matrix.
  factory :role, class: "Access::Role" do
    sequence(:key) { |n| "rol_de_prueba_#{n}" }
    scope_level { "organization" }
    system { false }
  end

  # A membership is created INSIDE a tenant (`create_in(org, :membership)`), like other tenant models. The role is a system
  # role, synced when the suite boots. Defaults to org_admin of the active organization; for other scopes use `role_key:`,
  # `company_id:` and `branch_id:`.
  factory :membership, class: "Access::Membership" do
    transient { role_key { "org_admin" } }

    organization { ActsAsTenant.current_tenant }
    user_id { create(:user).id }
    role { Access::Role.find_by!(key: role_key) }
  end
end
