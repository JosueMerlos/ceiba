require "rails_helper"

RSpec.describe Customers::Lookup do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:sibling) { create_in(organization, :company) }

  around { |example| with_tenant(organization) { example.run } }

  describe ".active_id?" do
    it "true para un cliente activo de la empresa" do
      customer = create(:customer, company:)

      expect(described_class.active_id?(id: customer.id, company:)).to be(true)
    end

    it "false para un cliente archivado" do
      customer = create(:customer, company:)
      Customers::Archive.call(customer:)

      expect(described_class.active_id?(id: customer.id, company:)).to be(false)
    end

    it "false para un cliente de otra empresa de la misma organización" do
      customer = create(:customer, company: sibling)

      expect(described_class.active_id?(id: customer.id, company:)).to be(false)
    end

    it "false para un id que no existe, nulo o que no es un uuid", :aggregate_failures do
      expect(described_class.active_id?(id: SecureRandom.uuid, company:)).to be(false)
      expect(described_class.active_id?(id: nil, company:)).to be(false)
      expect(described_class.active_id?(id: "no-es-uuid", company:)).to be(false)
    end

    it "devuelve solo un booleano: no expone ningún dato del cliente" do
      customer = create(:customer, company:)

      expect(described_class.active_id?(id: customer.id, company:)).to be_in([ true, false ])
    end
  end

  describe ".exists_id?" do
    it "true para un cliente de la empresa, también archivado: su historial sigue existiendo" do
      active = create(:customer, company:)
      archived = create(:customer, company:).tap { Customers::Archive.call(customer: it) }

      expect([ active, archived ].map { described_class.exists_id?(id: it.id, company:) }).to eq([ true, true ])
    end

    it "false para uno de otra empresa, inexistente o con un id que no es uuid" do
      foreign = create(:customer, company: sibling)

      expect([ foreign.id, SecureRandom.uuid, "no-es-uuid", nil ].map { described_class.exists_id?(id: it, company:) }).to eq([ false ] * 4)
    end
  end

  describe ".full_names" do
    it "devuelve id => nombre de los clientes pedidos, y solo el nombre" do
      first = create(:customer, company:, full_name: "Ana Ruiz")
      second = create(:customer, company:, full_name: "Luis Mora")
      create(:customer, company:, full_name: "No pedida")

      expect(described_class.full_names(ids: [ first.id, second.id ], company:)).to eq(first.id => "Ana Ruiz", second.id => "Luis Mora")
    end

    it "incluye a los clientes archivados: sus citas siguen existiendo" do
      customer = create(:customer, company:, full_name: "Ana Ruiz")
      Customers::Archive.call(customer:)

      expect(described_class.full_names(ids: [ customer.id ], company:)).to eq(customer.id => "Ana Ruiz")
    end

    it "ignora los clientes de otra empresa de la misma organización" do
      foreign = create(:customer, company: sibling)

      expect(described_class.full_names(ids: [ foreign.id ], company:)).to eq({})
    end

    it "sin ids no consulta y devuelve un hash vacío" do
      scoped_company = company
      queries = []
      counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }

      result = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { described_class.full_names(ids: [], company: scoped_company) }

      expect([ result, queries ]).to eq([ {}, [] ])
    end
  end
end
