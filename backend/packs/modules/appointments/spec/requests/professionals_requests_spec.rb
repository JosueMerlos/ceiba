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

  describe "contacto del profesional (teléfono y correo)" do
    let(:organization) { world.organization }
    let!(:ana) { professional_in(world.company_a, display_name: "Ana", phone_e164: "8888 1234", email: "ana@ej.com") }

    def company_show(professional) = "#{base(world.company_a)}/#{professional.id}"

    def branch_show(professional)
      "/api/v1/organizations/#{organization.id}/companies/#{world.company_a.id}/appointments/branches/#{world.branch_a1.id}/professionals/#{professional.id}"
    end

    def stored(id) = with_tenant(organization) { Appointments::Professional.find(id) }
    def branch_member(role, user: create(:user)) = sign_in(user_with_role(role, world, branch: world.branch_a1, user:))

    it "el company_manager crea con teléfono y correo: el teléfono queda en E.164 y el registro existe", :aggregate_failures do
      post base(world.company_a), params: { display_name: "Sandra", phone: "8888 5678", email: "  Sandra@Ej.com " },
                                  headers: manager_of(world.company_a).csrf_headers, as: :json

      expect(response).to have_http_status(:created)
      data = response.parsed_body["data"]
      expect(data).to include("display_name" => "Sandra", "phone" => "+50588885678", "email" => "sandra@ej.com")
      expect(stored(data["id"])).to have_attributes(phone_e164: "+50588885678", email: "sandra@ej.com")
    end

    it "crear con teléfono y correo vacíos los guarda como null, sin error", :aggregate_failures do
      post base(world.company_a), params: { display_name: "Sandra", phone: "", email: "" }, headers: manager_of(world.company_a).csrf_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["data"]).to include("phone" => nil, "email" => nil)
      expect(stored(response.parsed_body["data"]["id"])).to have_attributes(phone_e164: nil, email: nil)
    end

    it "un teléfono que no es un número real es 422 con el campo phone y no crea nada", :aggregate_failures do
      post base(world.company_a), params: { display_name: "Sandra", phone: "123" }, headers: manager_of(world.company_a).csrf_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "phone", "code" => "invalid"))
      expect(with_tenant(organization) { Appointments::Professional.where(display_name: "Sandra").count }).to eq(0)
    end

    it "el company_manager ve el contacto en el detalle de empresa" do
      get company_show(ana), headers: manager_of(world.company_a).csrf_headers

      expect(response.parsed_body["data"]).to include("id" => ana.id, "phone" => "+50588881234", "email" => "ana@ej.com")
    end

    %w[branch_manager receptionist].each do |role|
      it "el #{role} lee el detalle de empresa con phone y email en null", :aggregate_failures do
        get company_show(ana), headers: branch_member(role).csrf_headers

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"]).to include("id" => ana.id, "phone" => nil, "email" => nil)
      end
    end

    it "el professional no lee el detalle de empresa (403): no hay contacto que filtrar" do
      get company_show(ana), headers: branch_member("professional").csrf_headers

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("+50588881234")
    end

    it "desde la sucursal nadie recibe las claves de contacto, ni el company_manager ni el propio profesional", :aggregate_failures do
      person = create(:user)
      own_session = branch_member("professional", user: person)
      own = professional_in(world.company_a, display_name: "Propio", user_id: person.id, phone_e164: "8888 4321", email: "propio@ej.com")
      create_in(organization, :professional_branch_assignment, professional: own, branch: world.branch_a1)
      readers = { "company_manager" => manager_of(world.company_a), "branch_manager" => branch_member("branch_manager"), "professional" => own_session }

      bodies = readers.transform_values do |session|
        get branch_show(own), headers: session.csrf_headers
        [ response.status, response.parsed_body["data"]&.keys ]
      end

      bodies.each do |role, (status, keys)|
        expect(status).to eq(200), "#{role}: #{status}"
        expect(keys).to include("id"), "#{role}: #{keys.inspect}"
        expect(keys).not_to include("phone", "email"), "#{role}: #{keys.inspect}"
      end
    end

    it "el listado nunca trae las claves de contacto, para ningún rol", :aggregate_failures do
      sessions = { "company_manager" => manager_of(world.company_a), "branch_manager" => branch_member("branch_manager"),
                   "receptionist" => branch_member("receptionist") }

      sessions.each do |role, session|
        get base(world.company_a), headers: session.csrf_headers

        listed = response.parsed_body["data"]
        expect(listed.pluck("id")).to eq([ ana.id ]), role
        expect(listed.first.keys).not_to include("phone", "email"), role
        expect(response.body).not_to include("+50588881234"), role
      end
    end

    it "las respuestas de fijar servicios y de asignar a una sucursal no traen las claves de contacto", :aggregate_failures do
      headers = manager_of(world.company_a).csrf_headers
      service = create_in(organization, :service, company: world.company_a)

      put "#{company_show(ana)}/services", params: { service_ids: [ service.id ] }, headers:, as: :json
      services_keys = [ response.status, response.parsed_body["data"].keys ]
      put "#{branch_show(ana)}/assignment", headers:, as: :json
      assignment_keys = [ response.status, response.parsed_body["data"].keys ]

      expect(services_keys.first).to eq(200)
      expect(services_keys.last).to include("service_ids")
      expect(services_keys.last).not_to include("phone", "email")
      expect(assignment_keys.first).to eq(200)
      expect(assignment_keys.last).to include("branch_ids")
      expect(assignment_keys.last).not_to include("phone", "email")
    end

    it "editar teléfono y correo audita el nombre del campo y nunca el valor", :aggregate_failures do
      patch company_show(ana), params: { phone: "+505 8777 0000", email: "nueva@ej.com" }, headers: manager_of(world.company_a).csrf_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]).to include("phone" => "+50587770000", "email" => "nueva@ej.com")
      event = with_tenant(organization) { Audit::Event.where(action: "professional.updated", auditable_id: ana.id).sole }
      expect(event.before).to include("phone_e164" => "[FILTERED]", "email" => "[FILTERED]")
      expect(event.after).to include("phone_e164" => "[FILTERED]", "email" => "[FILTERED]")
      row = event.attributes.to_json
      [ "88881234", "87770000", "ana@ej.com", "nueva@ej.com" ].each { expect(row).not_to include(it) }
    end

    it "un null explícito borra el teléfono y el correo", :aggregate_failures do
      patch company_show(ana), params: { phone: nil, email: nil }, headers: manager_of(world.company_a).csrf_headers, as: :json

      expect(response.parsed_body["data"]).to include("phone" => nil, "email" => nil)
      expect(stored(ana.id)).to have_attributes(phone_e164: nil, email: nil)
    end

    it "el company_manager de OTRA organización recibe 404 y ningún dato de contacto", :aggregate_failures do
      other = build_access_world
      sign_in(user_with_role("company_manager", other, company: other.company_a))

      get company_show(ana)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("+50588881234")
    end
  end
end
