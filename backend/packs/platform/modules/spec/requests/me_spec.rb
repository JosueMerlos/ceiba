require "rails_helper"

# GET /api/v1/me (M0.09): el contexto elegido (parámetros o el último usado), los módulos ACTIVOS con sus settings resueltos, los
# permisos que ejerce y la navegación. La SPA solo REFLEJA esto; el control de acceso es del backend (05).
RSpec.describe "GET /api/v1/me" do
  include_context "con el módulo sample sincronizado"

  let(:world) { build_access_world }
  let(:organization) { world.organization }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }

  def me(params = {}) = get("/api/v1/me", params:)
  def data = response.parsed_body["data"]
  def enable(key, company = world.company_a) = with_tenant(organization) { Modules::Enable.call(company:, key:) }

  it "sin sesión: 401" do
    me

    expect(response).to have_http_status(:unauthorized)
  end

  describe "criterio 7: el dueño de una organización recién provisionada" do
    let(:owner) { Identity::ProvisionUser.call(email: "dueno@ceiba.test", full_name: "Rosa Mendoza", password: AuthenticationHelpers::DEFAULT_PASSWORD) }
    let(:provisioned) do
      Tenancy::ProvisionOrganization.call(
        organization: { name: "Barbería" }, company: { name: "Barbería", slug: "barberia-me", business_type: "barbershop", currency: "NIO" },
        branch: { name: "Centro", time_zone: "America/Managua" }, extras: { owner: }
      )
    end

    before do
      provisioned
      sign_in(owner)
      me
    end

    it "responde 200 con la identidad del principal" do
      expect(response).to have_http_status(:ok)
      expect(data["principal"]).to eq("id" => owner.id, "name" => "Rosa Mendoza", "email" => "dueno@ceiba.test")
    end

    it "el contexto por defecto es su organización y su empresa, sin sucursal" do
      expect(data["context"]).to match(
        "organization" => include("id" => provisioned.organization.id, "name" => "Barbería"),
        "company" => include("id" => provisioned.company.id, "slug" => "barberia-me"),
        "branch" => nil
      )
    end

    it "incluye appointments activo con sus settings por defecto" do
      expect(data["modules"]).to eq([ { "key" => "appointments", "version" => "1.0", "settings" => Modules.registry.fetch("appointments").defaults } ])
    end

    it "incluye sus permisos (de plataforma y el de conteos de citas, no el detalle de citas)" do
      expect(data["permissions"]).to include("platform.company.read", "platform.company_module.manage", "appointments.appointment.count")
      expect(data["permissions"]).not_to include("appointments.appointment.read")
    end

    it "incluye la navegación del módulo permitida por sus permisos" do
      expect(data["navigation"]).to eq([ { "module" => "appointments", "key" => "summary", "path" => "/agenda/summary" } ])
    end
  end

  describe "módulos activos e inactivos" do
    before do
      enable("sample")
      sign_in(manager)
    end

    it "solo lista los activos en la empresa del contexto" do
      me

      expect(data["modules"].pluck("key")).to eq(%w[sample])
    end

    it "los permisos y la navegación de un módulo inactivo desaparecen", :aggregate_failures do
      me
      active_permissions = data["permissions"]
      with_tenant(organization) { Modules::Disable.call(company: world.company_a, key: "sample") }
      me

      expect(active_permissions).to include("sample.thing.manage")
      expect(data["permissions"].grep(/\Asample\./)).to be_empty
      expect(data["navigation"].pluck("module")).not_to include("sample")
      expect(data["modules"]).to be_empty
    end

    it "la navegación se filtra por permiso: un recepcionista ve las entradas que su permiso permite" do
      sign_in(user_with_role("receptionist", world, company: nil, branch: world.branch_a1))
      me({ organization_id: organization.id, company_id: world.company_a.id })

      expect(data["navigation"]).to eq([ { "module" => "sample", "key" => "things", "path" => "/things" } ])
    end

    it "settings resueltos: default -> empresa -> sucursal del contexto" do
      with_tenant(organization) do
        Modules::UpdateSettings.call(company: world.company_a, key: "sample", settings: { "max_advance_days" => 30 })
        Modules::UpdateSettings.call(company: world.company_a, key: "sample", settings: { "min_lead_time_minutes" => 60 }, branch: world.branch_a1)
      end
      me({ company_id: world.company_a.id, branch_id: world.branch_a1.id, organization_id: organization.id })
      with_branch = data.dig("modules", 0, "settings")
      me({ company_id: world.company_a.id, organization_id: organization.id })

      expect(with_branch).to include("min_lead_time_minutes" => 60, "max_advance_days" => 30)
      expect(data.dig("modules", 0, "settings")).to include("min_lead_time_minutes" => 120, "max_advance_days" => 30)
    end
  end

  describe "el contexto" do
    let(:admin) { user_with_role("org_admin", world) }

    before { sign_in(admin) }

    it "por parámetros: organización, empresa y sucursal" do
      me({ organization_id: organization.id, company_id: world.company_b.id, branch_id: world.branch_b1.id })

      expect(data["context"]).to match("organization" => include("id" => organization.id), "company" => include("id" => world.company_b.id), "branch" => include("id" => world.branch_b1.id))
    end

    it "sin parámetros elige la primera empresa que ve (por id)" do
      me

      expect(data.dig("context", "company", "id")).to eq([ world.company_a.id, world.company_b.id ].min)
    end

    it "una empresa que el usuario no ve: 404, como siempre" do
      sign_in(manager)
      me({ organization_id: organization.id, company_id: world.company_b.id })

      expect(response).to have_http_status(:not_found)
    end

    it "una organización ajena o inexistente: 404" do
      me({ organization_id: "0198f0a0-0000-7000-8000-000000000000" })

      expect(response).to have_http_status(:not_found)
    end

    it "company_id sin organization_id: 400 request.invalid" do
      me({ company_id: world.company_a.id })

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["code"]).to eq("request.invalid")
    end

    it "una organización suspendida elegida expresamente: 403" do
      organization.update!(status: "suspended")
      me({ organization_id: organization.id })

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("access.organization_suspended")
    end

    it "una organización de otro mundo (sin membership) es 404: el parámetro se valida contra los memberships" do
      other = build_access_world
      me({ organization_id: other.organization.id })

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "el último contexto usado (cookie firmada, por navegador)" do
    before { sign_in(user_with_role("org_admin", world)) }

    it "sin parámetros devuelve el último contexto que se eligió" do
      me({ organization_id: organization.id, company_id: world.company_b.id, branch_id: world.branch_b1.id })
      me

      expect(data["context"]).to match("organization" => include("id" => organization.id), "company" => include("id" => world.company_b.id), "branch" => include("id" => world.branch_b1.id))
    end

    it "la cookie es firmada y HttpOnly" do
      me({ organization_id: organization.id, company_id: world.company_b.id })

      expect(response.headers["Set-Cookie"]).to match(/ceiba_context=[^;]+--[0-9a-f]+;.*httponly/i)
    end

    it "una cookie manipulada se ignora (vuelve al contexto por defecto)" do
      me({ organization_id: organization.id, company_id: world.company_b.id })
      cookies[Modules::ContextCookie.name] = "manipulada"
      me

      expect(response).to have_http_status(:ok)
      expect(data.dig("context", "company", "id")).to eq([ world.company_a.id, world.company_b.id ].min)
    end

    it "si perdió el acceso a lo recordado, cae al contexto por defecto en vez de fallar" do
      member = user_with_role("company_manager", world, company: world.company_b)
      sign_in(member)
      me({ organization_id: organization.id, company_id: world.company_b.id })
      with_tenant(organization) { Access::Membership.where(user_id: member.id).delete_all }
      user_with_role("company_manager", world, company: world.company_a, user: member)
      me

      expect(data.dig("context", "company", "id")).to eq(world.company_a.id)
    end
  end

  describe "un setting persistido que ya no cumple el esquema (sonda P5: antes dejaba /me en 422)" do
    before do
      enable("sample")
      with_tenant(organization) { Modules::CompanyModule.find_by!(company_id: world.company_a.id, module_key: "sample").update!(settings: { "max_advance_days" => 0 }) }
      sign_in(manager)
    end

    it "no rompe /me: el módulo sigue activo con los defaults y se reporta el problema" do
      allow(Rails.error).to receive(:report)
      me

      expect(response).to have_http_status(:ok)
      expect(data["modules"]).to eq([ { "key" => "sample", "version" => "1.0", "settings" => Modules.registry.fetch("sample").defaults } ])
      expect(Rails.error).to have_received(:report).with(an_instance_of(Modules::InvalidSettings), hash_including(handled: true, context: hash_including(module: "sample")))
    end

    it "el resto de los módulos no se ve afectado" do
      allow(Rails.error).to receive(:report)
      enable("sample_addon")
      me

      expect(data["modules"].pluck("key")).to eq(%w[sample sample_addon])
    end
  end

  describe "la cookie del último contexto está ligada al usuario" do
    it "otro usuario en el mismo navegador no hereda el contexto recordado" do
      sign_in(user_with_role("org_admin", world))
      me({ organization_id: organization.id, company_id: world.company_b.id })
      remembered = cookies[Modules::ContextCookie.name]
      other = user_with_role("org_admin", world)
      sign_in(other)
      cookies[Modules::ContextCookie.name] = remembered
      me

      expect(data.dig("context", "company", "id")).to eq([ world.company_a.id, world.company_b.id ].min)
    end

    it "el mismo usuario sí recupera su contexto" do
      sign_in(user_with_role("org_admin", world))
      me({ organization_id: organization.id, company_id: world.company_b.id })
      me

      expect(data.dig("context", "company", "id")).to eq(world.company_b.id)
    end
  end

  describe "un usuario sin memberships" do
    it "recibe 200 con el contexto vacío (la SPA decide qué mostrar)" do
      sign_in(create(:user))
      me

      expect(data).to include("context" => { "organization" => nil, "company" => nil, "branch" => nil }, "modules" => [], "permissions" => [], "navigation" => [])
    end
  end

  describe "consultas" do
    def module_queries
      statements = []
      callback = ->(*, payload) { statements << payload[:sql] if payload[:sql].match?(/company_modules|branch_module_settings/) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { me({ organization_id: organization.id, company_id: world.company_a.id }) }
      statements.size
    end

    it "no crece con el número de módulos activos (sin N+1)" do
      sign_in(manager)
      enable("sample")
      one = module_queries
      enable("sample_addon")
      two = module_queries

      expect(two).to be <= one
    end
  end

  describe "solo lectura" do
    it "no escribe nada en la base (GET en transacción de solo lectura)" do
      sign_in(manager)

      expect { me }.not_to(change { [ Modules::CompanyModule.unscoped.count, Audit::Event.unscoped.count ] })
    end
  end
end
