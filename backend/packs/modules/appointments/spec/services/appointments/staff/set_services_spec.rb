require "rails_helper"

RSpec.describe Appointments::Staff::SetServices do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:professional) { create_in(organization, :professional, company:) }
  let(:corte) { create_in(organization, :service, company:) }
  let(:barba) { create_in(organization, :service, company:) }

  def events(action) = Audit::Event.where(action:).to_a
  def service_ids = Appointments::ProfessionalService.where(professional_id: professional.id).pluck(:service_id)

  it "fija el conjunto de servicios y lo audita con el antes y el después", :aggregate_failures do
    with_tenant(organization) do
      create(:professional_service, professional:, service: corte)

      described_class.call(professional:, service_ids: [ barba.id ])

      expect(service_ids).to eq([ barba.id ])
      event = events("professional.services_set").sole
      expect([ event.before, event.after ]).to eq([ { "service_ids" => [ corte.id ] }, { "service_ids" => [ barba.id ] } ])
    end
  end

  it "conserva los vínculos que siguen en el conjunto (no los recrea)" do
    with_tenant(organization) do
      kept = create(:professional_service, professional:, service: corte)

      described_class.call(professional:, service_ids: [ corte.id, barba.id ])

      expect(Appointments::ProfessionalService.find(kept.id).service_id).to eq(corte.id)
      expect(service_ids).to contain_exactly(corte.id, barba.id)
    end
  end

  it "con una lista vacía quita todos; los repetidos cuentan una vez", :aggregate_failures do
    with_tenant(organization) do
      described_class.call(professional:, service_ids: [ corte.id, corte.id ])
      expect(service_ids).to eq([ corte.id ])

      described_class.call(professional:, service_ids: [])
      expect(service_ids).to be_empty
    end
  end

  it "no audita si el conjunto no cambió" do
    with_tenant(organization) do
      create(:professional_service, professional:, service: corte)

      described_class.call(professional:, service_ids: [ corte.id ])

      expect(events("professional.services_set")).to be_empty
    end
  end

  it "un servicio de otra empresa (o inexistente) lanza RecordInvalid (service_ids: invalid) y no cambia nada", :aggregate_failures do
    with_tenant(organization) do
      create(:professional_service, professional:, service: corte)
      foreign = create(:service, company: create(:company))

      expect { described_class.call(professional:, service_ids: [ barba.id, foreign.id ]) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:service_ids).map(&:type)).to eq([ :invalid ]) }
      expect { described_class.call(professional:, service_ids: [ SecureRandom.uuid ]) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(service_ids).to eq([ corte.id ])
      expect(events("professional.services_set")).to be_empty
    end
  end

  it "un servicio archivado no se puede añadir, pero uno ya vinculado que se archivó después puede seguir en el conjunto", :aggregate_failures do
    with_tenant(organization) do
      create(:professional_service, professional:, service: corte)
      corte.update!(archived_at: Time.current)
      archived_new = create(:service, company:, archived_at: Time.current)

      expect { described_class.call(professional:, service_ids: [ corte.id, archived_new.id ]) }.to raise_error(ActiveRecord::RecordInvalid)
      expect { described_class.call(professional:, service_ids: [ corte.id, barba.id ]) }.not_to raise_error
      expect(service_ids).to contain_exactly(corte.id, barba.id)
    end
  end
end
