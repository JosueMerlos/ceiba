require "rails_helper"

RSpec.describe Appointments::Staff::CreateProfessional do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:person) { create(:user) }

  def events(action) = Audit::Event.where(action:).to_a

  it "crea el profesional en la empresa y lo audita con el después", :aggregate_failures do
    with_tenant(organization) do
      professional = described_class.call(company_id: company.id, attributes: { display_name: "  Sandra Gómez ", active: false })

      expect(professional).to be_persisted
      expect(professional).to have_attributes(company_id: company.id, organization_id: organization.id, display_name: "Sandra Gómez", active: false, user_id: nil)
      event = events("professional.created").sole
      expect(event.before).to be_nil
      expect(event.after).to include("display_name" => "Sandra Gómez", "active" => false)
    end
  end

  it "vincula a la persona si es miembro de la organización" do
    user_with_role("receptionist", organization, branch: create_in(organization, :branch, company:), user: person)

    with_tenant(organization) do
      professional = described_class.call(company_id: company.id, attributes: { display_name: "Sandra", user_id: person.id })

      expect(professional.reload.user_id).to eq(person.id)
    end
  end

  it "ignora los atributos que un cliente no puede escribir (company_id, archived_at)", :aggregate_failures do
    other_company = create_in(organization, :company)

    with_tenant(organization) do
      professional = described_class.call(company_id: company.id, attributes: { display_name: "Ana", company_id: other_company.id, archived_at: Time.current })

      expect(professional.company_id).to eq(company.id)
      expect(professional.archived_at).to be_nil
    end
  end

  it "con una persona sin membresía lanza RecordInvalid y no deja nada ni audita", :aggregate_failures do
    with_tenant(organization) do
      expect { described_class.call(company_id: company.id, attributes: { display_name: "Ana", user_id: person.id }) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:user_id).map(&:type)).to eq([ :invalid ]) }
      expect(Appointments::Professional.count).to eq(0)
      expect(events("professional.created")).to be_empty
    end
  end
end
