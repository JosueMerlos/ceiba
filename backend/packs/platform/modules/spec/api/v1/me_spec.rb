require "swagger_helper"

# GET /api/v1/me contract. Each `response` runs the real request and validates the body against the schema.
RSpec.describe "API v1: yo (contexto, módulos, permisos y navegación)" do
  let(:world) { build_access_world }

  path "/api/v1/me" do
    get "Contexto del usuario autenticado" do
      tags "Contexto"
      description "El contexto elegido (organización, empresa y sucursal), los módulos ACTIVOS en esa empresa con sus settings resueltos " \
                  "(default del esquema, empresa, sucursal), los permisos que el usuario ejerce ahí y la navegación permitida. " \
                  "El frontend solo lo REFLEJA: ocultar algo no es control de acceso. Sin parámetros usa el último contexto elegido " \
                  "(cookie firmada `ceiba_context`) o, si no hay, la primera organización y empresa que el usuario ve. " \
                  "Un usuario sin memberships recibe el contexto vacío."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :organization_id, in: :query, schema: { type: :string, format: :uuid }, required: false, description: "Requerido si se pasa company_id"
      parameter name: :company_id, in: :query, schema: { type: :string, format: :uuid }, required: false
      parameter name: :branch_id, in: :query, schema: { type: :string, format: :uuid }, required: false, description: "Requiere company_id"

      response "200", "el contexto del usuario" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:organization_id) { world.organization.id }
        let(:company_id) { world.company_a.id }
        let(:branch_id) { world.branch_a1.id }

        before { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") } }

        schema "$ref" => "#/components/schemas/Me"

        run_test! do |response|
          data = response.parsed_body["data"]
          expect(data["modules"].pluck("key")).to eq(%w[appointments])
          expect(data["context"]["branch"]["id"]).to eq(branch_id)
          expect(data["permissions"]).to include("appointments.appointment.create")
        end
      end

      response "200", "company_permissions: el company_manager tiene en el alcance de empresa las claves de ausencias" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:organization_id) { world.organization.id }
        let(:company_id) { world.company_a.id }
        let(:branch_id) { world.branch_a1.id }

        before { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") } }

        schema "$ref" => "#/components/schemas/Me"

        run_test! do |response|
          expect(response.parsed_body["data"]["company_permissions"]).to include("appointments.time_off.read", "appointments.time_off.manage")
        end
      end

      response "200", "company_permissions: un branch_manager de una sola sucursal, sin sucursal en el contexto, no tiene claves de ausencias de empresa" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }

        before { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") } }

        schema "$ref" => "#/components/schemas/Me"

        run_test! do |response|
          data = response.parsed_body["data"]
          expect(data["context"]["branch"]).to be_nil
          # `permissions` merges the keys of its branch membership; `company_permissions` does not.
          expect(data["permissions"]).to include("appointments.time_off.read")
          expect(data["company_permissions"]).not_to include("appointments.time_off.read", "appointments.time_off.manage")
        end
      end

      response "200", "company_permissions: el receptionist (solo sucursal) no tiene claves de ausencias de empresa" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }

        before { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") } }

        schema "$ref" => "#/components/schemas/Me"

        run_test! { |response| expect(response.parsed_body["data"]["company_permissions"].grep(/time_off/)).to be_empty }
      end

      %w[org_owner org_admin].each do |role|
        response "200", "company_permissions: el #{role} tiene solo lo que su membership de organización concede, sin claves de ausencias" do
          let!(:signed_in) { sign_in(user_with_role(role, world)) }

          before { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") } }

          schema "$ref" => "#/components/schemas/Me"

          run_test! do |response|
            data = response.parsed_body["data"]
            expect(data["context"]["company"]["id"]).to eq(world.company_a.id)
            expect(data["company_permissions"]).to include("platform.company.read")
            expect(data["company_permissions"].grep(/time_off/)).to be_empty
          end
        end
      end

      response "200", "company_permissions: vacío sin empresa en el contexto" do
        let!(:signed_in) { sign_in(create(:user)) }

        schema "$ref" => "#/components/schemas/Me"

        run_test! { |response| expect(response.parsed_body["data"]).to include("company_permissions" => []) }
      end

      response "400", "company_id o branch_id sin su organización/empresa" do
        let!(:signed_in) { sign_in(user_with_role("org_admin", world)) }
        let(:company_id) { world.company_a.id }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("request.invalid") }
      end

      response "401", "sin sesión válida" do
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "la organización elegida está suspendida (`access.organization_suspended`)" do
        let!(:signed_in) { sign_in(user_with_role("org_admin", world)).tap { world.organization.update!(status: "suspended") } }
        let(:organization_id) { world.organization.id }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.organization_suspended") }
      end

      response "404", "la organización, empresa o sucursal no existe o el usuario no la ve" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:organization_id) { world.organization.id }
        let(:company_id) { world.company_b.id }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end
    end
  end
end
