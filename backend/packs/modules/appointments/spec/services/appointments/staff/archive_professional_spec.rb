require "rails_helper"

RSpec.describe Appointments::Staff::ArchiveProfessional do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }

  def events(action) = Audit::Event.where(action:).to_a

  it "archiva (no borra) y audita", :aggregate_failures do
    with_tenant(organization) do
      professional = create(:professional, company:)

      freeze_time do
        described_class.call(professional:)

        expect(professional.reload.archived_at).to eq(Time.current)
      end
      expect(Appointments::Professional.where(id: professional.id)).to exist
      expect(events("professional.archived").sole.after).to include("archived_at" => be_present)
    end
  end

  it "es idempotente: archivar uno archivado no cambia la fecha ni audita otra vez", :aggregate_failures do
    with_tenant(organization) do
      professional = create(:professional, company:)
      described_class.call(professional:)
      first = professional.reload.archived_at

      travel(1.hour) { described_class.call(professional:) }

      expect(professional.reload.archived_at).to eq(first)
      expect(events("professional.archived").size).to eq(1)
    end
  end

  it "conserva sus asignaciones y servicios (la historia sigue apuntando a ellos)", :aggregate_failures do
    with_tenant(organization) do
      professional = create(:professional, company:)
      create(:professional_branch_assignment, professional:)
      create(:professional_service, professional:)

      described_class.call(professional:)

      expect(Appointments::ProfessionalBranchAssignment.where(professional_id: professional.id).count).to eq(1)
      expect(Appointments::ProfessionalService.where(professional_id: professional.id).count).to eq(1)
    end
  end
end
