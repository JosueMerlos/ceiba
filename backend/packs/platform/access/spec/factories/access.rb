FactoryBot.define do
  # Roles de sistema por clave y alcance. Los crea Access.sync! con sus permisos; la factory solo reutiliza o crea el rol.
  factory :role, class: "Access::Role" do
    sequence(:key) { |n| "rol_#{n}" }
    scope_level { "organization" }
  end

  # Un membership se crea DENTRO de un tenant (`create_in(org, :membership)`), como el resto de modelos tenant. Por defecto:
  # org_admin de la organización activa. Para otros alcances: `role_key:`, `company_id:` y `branch_id:`.
  factory :membership, class: "Access::Membership" do
    transient do
      role_key { "org_admin" }
      level { { "org_admin" => "organization", "org_owner" => "organization", "company_manager" => "company" }.fetch(role_key, "branch") }
    end

    organization { ActsAsTenant.current_tenant }
    user_id { create(:user).id }
    role { Access::Role.find_by(key: role_key) || create(:role, key: role_key, scope_level: level) }
  end
end
