require "rails_helper"

RSpec.describe Appointments::Catalog::UpsertOverride do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:service) { create_in(organization, :service, company:) }

  def events(action) = Audit::Event.where(action:).to_a
  def call(attributes, **options, &) = described_class.call(service:, branch_id: branch.id, attributes:, **options, &)

  it "crea el override y lo audita con el después", :aggregate_failures do
    with_tenant(organization) do
      override = call({ duration_minutes: 45 })

      expect(override).to be_persisted
      expect(override).to have_attributes(company_id: company.id, branch_id: branch.id, service_id: service.id, duration_minutes: 45, price_minor: nil)
      event = events("service_override.set").sole
      expect(event.before).to be_nil
      expect(event.after).to eq("duration_minutes" => 45, "price_minor" => nil)
      expect(event.metadata).to include("branch_id" => branch.id, "service_id" => service.id)
    end
  end

  it "con un override existente MEZCLA: cambia lo enviado y conserva lo que no viene" do
    with_tenant(organization) do
      existing = create(:branch_service_override, service:, branch:, duration_minutes: 45, price_minor: 30_000)

      updated = call({ duration_minutes: 50 })

      expect(updated.id).to eq(existing.id)
      expect(updated.reload).to have_attributes(duration_minutes: 50, price_minor: 30_000)
      event = events("service_override.set").sole
      expect([ event.before, event.after ]).to eq([ { "duration_minutes" => 45 }, { "duration_minutes" => 50 } ])
    end
  end

  it "un null explícito quita ese valor y se conserva el otro" do
    with_tenant(organization) do
      create(:branch_service_override, service:, branch:, duration_minutes: 45, price_minor: 30_000)

      override = call({ price_minor: nil })

      expect(override.reload).to have_attributes(duration_minutes: 45, price_minor: nil)
    end
  end

  it "dejar el override sin duración ni precio lanza RecordInvalid y no cambia nada (para quitarlo se usa RemoveOverride)" do
    with_tenant(organization) do
      create(:branch_service_override, service:, branch:, duration_minutes: nil, price_minor: 30_000)

      expect { call({ price_minor: nil }) }.to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:base).map(&:type)).to eq([ :empty ]) }
      expect(Appointments::BranchServiceOverride.sole.price_minor).to eq(30_000)
    end
  end

  it "una sucursal de otra empresa lanza RecordInvalid (branch_id: invalid) y no crea nada" do
    with_tenant(organization) do
      foreign_branch = create(:branch, company: create(:company))

      expect { described_class.call(service:, branch_id: foreign_branch.id, attributes: { duration_minutes: 45 }) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:branch_id).map(&:type)).to eq([ :invalid ]) }
      expect(Appointments::BranchServiceOverride.count).to eq(0)
    end
  end

  describe "autorización sobre la fila ACTUAL" do
    it "el bloque recibe el override candidato con lo que cambiaría y, si lanza, no se escribe ni audita nada", :aggregate_failures do
      with_tenant(organization) do
        create(:branch_service_override, service:, branch:, duration_minutes: 45, price_minor: 30_000)
        seen = nil

        expect { call({ price_minor: 1 }) { |candidate| seen = candidate.changed; raise "denied" } }.to raise_error("denied")

        expect(seen).to eq([ "price_minor" ])
        expect(Appointments::BranchServiceOverride.sole.price_minor).to eq(30_000)
        expect(events("service_override.set")).to be_empty
      end
    end
  end

  # Simulates losing the race: the first lookup finds nothing and the INSERT of the new row hits the unique index.
  def simulate_lost_race
    real_find = Appointments::BranchServiceOverride.method(:find_by)
    lookups = 0
    allow(Appointments::BranchServiceOverride).to receive(:find_by) { |*args, **kwargs| (lookups += 1) == 1 ? nil : real_find.call(*args, **kwargs) }
    real_new = Appointments::BranchServiceOverride.method(:new)
    allow(Appointments::BranchServiceOverride).to receive(:new) do |*args, **kwargs|
      real_new.call(*args, **kwargs).tap { |loser| allow(loser).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique) }
    end
  end

  it "ante una carrera (RecordNotUnique en el INSERT) reintenta como actualización sobre la fila ganadora", :aggregate_failures do
    with_tenant(organization) do
      winner = create(:branch_service_override, service:, branch:, duration_minutes: 45, price_minor: 30_000)
      simulate_lost_race

      override = call({ duration_minutes: 60 })

      expect(override.id).to eq(winner.id)
      expect(winner.reload).to have_attributes(duration_minutes: 60, price_minor: 30_000)
      expect(Appointments::BranchServiceOverride.count).to eq(1)
    end
  end

  # Simulates a competitor that COMMITTED between our lookup and our save: the lookup finds nothing, the validation sees the row.
  def simulate_committed_competitor
    real_find = Appointments::BranchServiceOverride.method(:find_by)
    lookups = 0
    allow(Appointments::BranchServiceOverride).to receive(:find_by) { |*args, **kwargs| (lookups += 1) == 1 ? nil : real_find.call(*args, **kwargs) }
  end

  it "si el competidor ya confirmó (la validación de unicidad lo ve) reintenta como actualización y autoriza el cambio efectivo", :aggregate_failures do
    with_tenant(organization) do
      winner = create(:branch_service_override, service:, branch:, duration_minutes: 45, price_minor: 30_000)
      simulate_committed_competitor
      seen = []

      override = call({ duration_minutes: 60 }) { |candidate| seen << [ candidate.persisted?, candidate.changed ] }

      expect(override.id).to eq(winner.id)
      expect(winner.reload).to have_attributes(duration_minutes: 60, price_minor: 30_000)
      expect(Appointments::BranchServiceOverride.count).to eq(1)
      expect(seen.last).to eq([ true, [ "duration_minutes" ] ])
    end
  end

  it "un RecordInvalid que no es de unicidad no se reintenta" do
    with_tenant(organization) do
      expect { call({ duration_minutes: 0 }) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
