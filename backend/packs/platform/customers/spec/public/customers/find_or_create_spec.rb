require "rails_helper"

RSpec.describe Customers::FindOrCreate do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:other_company) { create_in(organization, :company) }

  def call(**overrides)
    described_class.call(company_id: company.id, full_name: "Ana López", phone: "8888-7777", **overrides)
  end

  def events(*actions) = Audit::Event.where(action: actions).order(:id).to_a

  it "crea el cliente con el teléfono normalizado cuando no existe" do
    with_tenant(organization) do
      customer = call(email: "Ana@Example.com")

      expect(customer).to be_persisted
      expect(customer.reload.attributes.slice("full_name", "phone_e164", "email", "company_id", "organization_id", "archived_at")).to eq(
        "full_name" => "Ana López", "phone_e164" => "+50588887777", "email" => "ana@example.com",
        "company_id" => company.id, "organization_id" => organization.id, "archived_at" => nil
      )
    end
  end

  it "devuelve el existente sin duplicarlo ni modificarlo, aunque el teléfono llegue con otro formato", :aggregate_failures do
    with_tenant(organization) do
      existing = call
      again = call(full_name: "Otro Nombre", phone: "+505 8888 7777", email: "otro@example.com")

      expect(again.id).to eq(existing.id)
      expect(Customers::Customer.count).to eq(1)
      expect(again.reload.attributes.slice("full_name", "email")).to eq("full_name" => "Ana López", "email" => nil)
      expect(events("customer.created", "customer.updated").size).to eq(1)
    end
  end

  it "el mismo teléfono en otra empresa crea otro cliente" do
    with_tenant(organization) do
      mine = call
      theirs = call(company_id: other_company.id)

      expect(theirs.id).not_to eq(mine.id)
      expect(Customers::Customer.pluck(:company_id)).to contain_exactly(company.id, other_company.id)
    end
  end

  it "audita solo la creación y el evento no contiene el nombre, el teléfono ni el correo", :aggregate_failures do
    with_tenant(organization) do
      customer = call(email: "ana@example.com")
      call

      created = events("customer.created")
      expect(created.size).to eq(1)
      event = created.first
      expect([ event.auditable_type, event.auditable_id ]).to eq([ "Customers::Customer", customer.id ])
      expect(event.metadata).to eq("changed" => %w[full_name phone_e164 email])
      serialized = event.attributes.slice("before", "after", "metadata").to_json
      expect(serialized).not_to match(/Ana|López|8888|7777|example/i)
    end
  end

  it "con un teléfono inválido lanza ActiveRecord::RecordInvalid con el registro y no escribe nada" do
    with_tenant(organization) do
      expect { call(phone: "123") }.to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:phone_e164).map(&:type)).to eq([ :invalid ]) }
      expect([ Customers::Customer.count, events("customer.created").size ]).to eq([ 0, 0 ])
    end
  end

  it "ante una carrera (RecordNotUnique en el INSERT) devuelve al cliente existente y no audita otra creación" do
    with_tenant(organization) do
      winner = call
      real_new = Customers::Customer.method(:new)
      allow(Customers::Customer).to receive(:with_phone).and_return(Customers::Customer.none, Customers::Customer.where(id: winner.id))
      allow(Customers::Customer).to receive(:new) do |*args, **kwargs|
        real_new.call(*args, **kwargs).tap { |loser| allow(loser).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique) }
      end

      customer = call

      expect(customer.id).to eq(winner.id)
      expect(Customers::Customer.count).to eq(1)
      expect(events("customer.created").size).to eq(1)
    end
  end

  it "si el competidor ya hizo commit entre la consulta y el guardado, devuelve al existente en vez de fallar la validación", :aggregate_failures do
    with_tenant(organization) do
      winner = call
      lookups = 0
      allow(Customers::Customer).to receive(:with_phone).and_wrap_original do |original, *args|
        (lookups += 1) == 1 ? Customers::Customer.none : original.call(*args)
      end

      customer = call(full_name: "Otro Nombre")

      expect(customer.id).to eq(winner.id)
      expect(Customers::Customer.count).to eq(1)
      expect(events("customer.created").size).to eq(1)
    end
  end

  context "con un cliente archivado del mismo teléfono" do
    it "lo restaura, actualiza nombre y correo si vienen y audita customer.restored", :aggregate_failures do
      with_tenant(organization) do
        archived = create(:customer, company:, full_name: "Nombre Viejo", phone_e164: "8888-7777", email: "viejo@example.com", archived_at: 1.day.ago)

        customer = call(full_name: "Ana López", email: "nuevo@example.com")

        expect(customer.id).to eq(archived.id)
        expect(customer.reload.attributes.slice("archived_at", "full_name", "email")).to eq("archived_at" => nil, "full_name" => "Ana López", "email" => "nuevo@example.com")
        expect(Customers::Customer.count).to eq(1)
        restored = events("customer.restored")
        expect(restored.size).to eq(1)
        expect(restored.first.metadata).to eq("changed" => %w[full_name email archived_at])
        expect(restored.first.attributes.slice("before", "after", "metadata").to_json).not_to match(/Ana|López|viejo|nuevo|8888|example/i)
      end
    end

    it "limpia el correo y las notas que la llamada no envía (el número pudo pasar a otra persona)", :aggregate_failures do
      with_tenant(organization) do
        archived = create(:customer, company:, phone_e164: "8888-7777", email: "viejo@example.com", notes: "alérgica al látex", archived_at: 1.day.ago)

        customer = call

        expect(customer.id).to eq(archived.id)
        expect(customer.reload.attributes.slice("email", "notes", "archived_at")).to eq("email" => nil, "notes" => nil, "archived_at" => nil)
        expect(events("customer.restored").first.metadata).to eq("changed" => %w[full_name email notes archived_at])
      end
    end
  end

  it "con un cliente activo no toca su correo ni sus notas", :aggregate_failures do
    with_tenant(organization) do
      active = create(:customer, company:, phone_e164: "8888-7777", email: "ana@example.com", notes: "prefiere tardes")

      call

      expect(active.reload.attributes.slice("email", "notes")).to eq("email" => "ana@example.com", "notes" => "prefiere tardes")
    end
  end
end
