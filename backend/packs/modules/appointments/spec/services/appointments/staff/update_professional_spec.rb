require "rails_helper"

RSpec.describe Appointments::Staff::UpdateProfessional do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:professional) { create_in(organization, :professional, company:, display_name: "Ana", active: true) }

  def events(action) = Audit::Event.where(action:).to_a

  it "cambia solo lo enviado y audita antes y después", :aggregate_failures do
    with_tenant(organization) do
      updated = described_class.call(professional:, attributes: { display_name: "Ana María" })

      expect(updated.reload).to have_attributes(display_name: "Ana María", active: true)
      event = events("professional.updated").sole
      expect([ event.before, event.after ]).to eq([ { "display_name" => "Ana" }, { "display_name" => "Ana María" } ])
    end
  end

  it "no audita si nada cambió" do
    with_tenant(organization) do
      described_class.call(professional:, attributes: { display_name: "Ana" })

      expect(events("professional.updated")).to be_empty
    end
  end

  it "nunca mueve el profesional a otra empresa ni lo desarchiva", :aggregate_failures do
    other_company = create_in(organization, :company)

    with_tenant(organization) do
      described_class.call(professional:, attributes: { display_name: "Ana", company_id: other_company.id, archived_at: nil })

      expect(professional.reload.company_id).to eq(company.id)
    end
  end

  it "un profesional archivado es historia de solo lectura (base: archived)", :aggregate_failures do
    with_tenant(organization) do
      archived = create(:professional, company:, archived_at: Time.current)

      expect { described_class.call(professional: archived, attributes: { display_name: "Otro" }) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(archived.reload.display_name).not_to eq("Otro")
    end
  end

  it "un nombre en blanco lanza RecordInvalid y conserva el anterior" do
    with_tenant(organization) do
      expect { described_class.call(professional:, attributes: { display_name: " " }) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(professional.reload.display_name).to eq("Ana")
    end
  end
end
