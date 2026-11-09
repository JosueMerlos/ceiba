FactoryBot.define do
  # Un membership se crea DENTRO de un tenant (`create_in(org, :membership)`), como el resto de modelos tenant. El rol sale
  # de los roles de sistema sincronizados al arrancar la suite (spec/support/access_catalog.rb). Por defecto: org_admin de
  # la organización activa; los alcances de empresa y sucursal se piden con `role_key:`, `company_id:` y `branch_id:`.
  factory :membership, class: "Access::Membership" do
    transient { role_key { "org_admin" } }

    organization { ActsAsTenant.current_tenant }
    user_id { create(:user).id }
    role { Access::Role.find_by!(key: role_key) }
  end
end
