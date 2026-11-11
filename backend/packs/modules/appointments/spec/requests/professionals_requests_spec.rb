require "rails_helper"

# Behavior of the professional endpoints that the contract specs do not describe: one person with a record in each company
# of the group, query counts and idempotent creation.
RSpec.describe "Profesionales: peticiones" do
  let(:world) { build_access_world }
  let(:person) { create(:user) }

  before do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
  end

  def base(company) = "/api/v1/organizations/#{world.organization.id}/companies/#{company.id}/appointments/professionals"
  def manager_of(company) = sign_in(user_with_role("company_manager", world, company:))
  def professional_in(company, **attributes) = create_in(world.organization, :professional, company:, **attributes)

  describe "una persona con registros en dos empresas del grupo" do
    # Declared before the records: the person must be a member of the organization to be linked.
    before { user_with_role("receptionist", world, branch: world.branch_a1, user: person) }

    let!(:in_a) { professional_in(world.company_a, display_name: "Sandra en A", user_id: person.id) }
    let!(:in_b) { professional_in(world.company_b, display_name: "Sandra en B", user_id: person.id) }

    it "cada empresa lista solo su registro, con su propio nombre" do
      get base(world.company_a), headers: manager_of(world.company_a).csrf_headers
      listed_in_a = response.parsed_body["data"]
      get base(world.company_b), headers: manager_of(world.company_b).csrf_headers
      listed_in_b = response.parsed_body["data"]

      expect(listed_in_a.pluck("id", "display_name")).to eq([ [ in_a.id, "Sandra en A" ] ])
      expect(listed_in_b.pluck("id", "display_name")).to eq([ [ in_b.id, "Sandra en B" ] ])
    end

    it "el registro de la empresa B no se encuentra desde la empresa A (404, no 403)" do
      get "#{base(world.company_a)}/#{in_b.id}", headers: manager_of(world.company_a).csrf_headers

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["code"]).to eq("resource.not_found")
    end
  end

  it "listar no hace consultas por profesional: sucursales y servicios se precargan en una consulta cada uno" do
    5.times do
      professional = professional_in(world.company_a)
      create_in(world.organization, :professional_branch_assignment, professional:, branch: world.branch_a1)
      create_in(world.organization, :professional_service, professional:)
    end
    headers = manager_of(world.company_a).csrf_headers
    queries = []
    subscriber = ->(*, payload) { queries << payload[:sql] if payload[:sql].match?(/FROM "professional_(branch_assignments|services)"/) }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { get base(world.company_a), headers: }

    expect(response.parsed_body["data"].size).to eq(5)
    expect(queries.size).to eq(2)
  end

  describe "Idempotency-Key al crear" do
    it "repetir la petición con la misma clave devuelve la misma respuesta y crea un solo profesional" do
      headers = manager_of(world.company_a).csrf_headers.merge("Idempotency-Key" => SecureRandom.uuid)

      post base(world.company_a), params: { display_name: "Ana" }, headers:, as: :json
      first = [ response.status, response.body ]
      post base(world.company_a), params: { display_name: "Ana" }, headers:, as: :json

      expect([ response.status, response.body ]).to eq(first)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
      expect(with_tenant(world.organization) { Appointments::Professional.count }).to eq(1)
    end
  end
end
