require "rails_helper"

RSpec.describe Appointments::Availability::ProfessionalChoice do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }

  it "any no nombra a nadie y of nombra al profesional", :aggregate_failures do
    with_tenant(organization) do
      person = create(:professional, company:)

      expect(described_class.any).to have_attributes(any?: true, named: [], cache_token: "any")
      expect(described_class.of(person)).to have_attributes(any?: false, named: [ person ], cache_token: person.id)
    end
  end

  it "resolve con :any no consulta el alcance" do
    expect(described_class.resolve(:any, within: nil)).to be_any
  end

  it "resolve busca al profesional en el alcance y es un 404 si no está en él", :aggregate_failures do
    with_tenant(organization) do
      inside = create(:professional, company:)
      outside = create(:professional, company:)
      scope = Appointments::Professional.where(id: inside.id)

      expect(described_class.resolve(inside.id, within: scope).professional).to eq(inside)
      expect { described_class.resolve(outside.id, within: scope) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
