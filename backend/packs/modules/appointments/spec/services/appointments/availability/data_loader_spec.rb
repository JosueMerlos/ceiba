require "rails_helper"

RSpec.describe Appointments::Availability::DataLoader do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:service) { create_in(organization, :service, company:) }
  let(:professional) { create_in(organization, :professional, company:) }

  def monday = Date.new(2026, 11, 16)

  around { |example| with_tenant(organization) { example.run } }

  before { Modules::Enable.call(company:, key: "appointments") }

  def load_for(services: [ service ], professional: Appointments::Availability::ProfessionalChoice.any)
    requirements = Appointments::ServiceResourceRequirement.where(service_id: services.map(&:id)).pluck(:service_id, :kind)
    described_class.call(company:, branch:, services:, professional:, from_date: monday, to_date: monday + 6, requirements:)
  end

  def provider_of(*services, assigned: branch)
    create_in(organization, :professional, company:).tap do |person|
      create(:professional_branch_assignment, professional: person, branch: assigned) if assigned
      services.each { create(:professional_service, professional: person, service: it) }
    end
  end

  def ids(owners) = owners.map { it.fetch(:id) }

  describe "profesionales elegibles con :any" do
    it "excluye a quien presta 2 de los 3 servicios pedidos y deja a quien presta los 3", :aggregate_failures do
      services = create_list(:service, 3, company:)
      complete = provider_of(*services)
      provider_of(*services.first(2))

      expect(ids(load_for(services:).professionals)).to eq([ complete.id ])
    end

    it "un servicio repetido en la lista no cuenta doble: quien lo presta sigue siendo elegible" do
      provider = provider_of(service)

      expect(ids(load_for(services: [ service, service ]).professionals)).to eq([ provider.id ])
    end

    it "no incluye a quien presta los servicios pero no está asignado a la sucursal, ni a un profesional archivado", :aggregate_failures do
      provider_of(service, assigned: nil)
      provider_of(service).update!(archived_at: Time.current)
      provider = provider_of(service)

      expect(ids(load_for.professionals)).to eq([ provider.id ])
    end

    it "un profesional concreto se carga tal cual, sin buscar a los demás" do
      provider_of(service)

      expect(ids(load_for(professional: Appointments::Availability::ProfessionalChoice.of(professional)).professionals)).to eq([ professional.id ])
    end
  end

  describe "recursos" do
    before { create(:service_resource_requirement, service:, kind: "room") }

    it "no carga una sala archivada, pausada ni de otra sucursal, y sí la de la sucursal", :aggregate_failures do
      room = create(:resource, branch:, kind: "room")
      create(:resource, branch:, kind: "room", archived_at: Time.current)
      create(:resource, branch:, kind: "room", active: false)
      create(:resource, branch: create(:branch, company:), kind: "room")

      expect(ids(load_for.resources)).to eq([ room.id ])
    end

    it "carga la ocupación de la sala por citas que bloquean, no por las canceladas", :aggregate_failures do
      room = create(:resource, branch:, kind: "room")
      person = provider_of(service)
      create(:appointment, professional: person, branch:, resource: room, starts_at: Time.utc(2026, 11, 16, 17), ends_at: Time.utc(2026, 11, 16, 17, 30))
      create(:appointment, professional: person, branch:, resource: room, status: "cancelled", starts_at: Time.utc(2026, 11, 17, 17),
                           ends_at: Time.utc(2026, 11, 17, 17, 30))

      busy = load_for.resources.first.fetch(:busy)

      expect(busy.map(&:starts_at)).to eq([ Time.utc(2026, 11, 16, 17) ])
    end
  end

  describe "aislamiento entre empresas" do
    it "las ausencias y los recursos de otra empresa de la misma organización no se cargan", :aggregate_failures do
      create(:service_resource_requirement, service:, kind: "room")
      room = create(:resource, branch:, kind: "room")
      provider = provider_of(service)
      other_company = create_in(organization, :company)
      other_branch = create_in(organization, :branch, company: other_company)
      create(:time_off, professional: create_in(organization, :professional, company: other_company), starts_at: Time.utc(2026, 11, 16, 17),
                        ends_at: Time.utc(2026, 11, 16, 18))
      create(:time_off, resource: create(:resource, branch: other_branch, kind: "room"), starts_at: Time.utc(2026, 11, 16, 17),
                        ends_at: Time.utc(2026, 11, 16, 18))

      loaded = load_for

      expect(loaded.professionals.map { [ it.fetch(:id), it.fetch(:time_offs) ] }).to eq([ [ provider.id, [] ] ])
      expect(loaded.resources.map { [ it.fetch(:id), it.fetch(:time_offs) ] }).to eq([ [ room.id, [] ] ])
    end

    it "carga solo las ausencias del propio profesional dentro del rango", :aggregate_failures do
      provider = provider_of(service)
      inside = create(:time_off, professional: provider, starts_at: Time.utc(2026, 11, 18, 17), ends_at: Time.utc(2026, 11, 18, 18))
      create(:time_off, professional: provider, starts_at: Time.utc(2024, 3, 1, 17), ends_at: Time.utc(2024, 3, 1, 18))

      offs = load_for.professionals.first.fetch(:time_offs)

      expect(offs.map(&:starts_at)).to eq([ inside.starts_at ])
    end
  end
end
