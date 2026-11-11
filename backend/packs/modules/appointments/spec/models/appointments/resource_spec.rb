require "rails_helper"

RSpec.describe Appointments::Resource do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:other_company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }

  def errors_of(resource, attribute) = resource.errors.where(attribute).map(&:type)

  it "es un recurso de una sucursal, con su empresa y su tipo", :aggregate_failures do
    with_tenant(organization) do
      resource = create(:resource, branch:, name: "  Sillón 1 ", kind: "room")

      expect(resource.reload).to have_attributes(name: "Sillón 1", kind: "room", branch_id: branch.id, company_id: company.id, active: true, archived_at: nil)
    end
  end

  it "acepta los tres tipos y rechaza otro (kind: inclusion)", :aggregate_failures do
    with_tenant(organization) do
      expect(%w[chair room equipment].map { build(:resource, branch:, kind: it) }).to all(be_valid)
      other = build(:resource, branch:, kind: "spaceship")

      expect(other).not_to be_valid
      expect(errors_of(other, :kind)).to eq([ :inclusion ])
    end
  end

  it "la base de datos también rechaza un tipo ajeno (CHECK)" do
    with_tenant(organization) do
      resource = build(:resource, branch:, kind: "spaceship")

      expect { savepoint { resource.save!(validate: false) } }.to raise_error(ActiveRecord::StatementInvalid, /chk_resources_kind/)
    end
  end

  it "el nombre es obligatorio y admite hasta 120 caracteres", :aggregate_failures do
    with_tenant(organization) do
      expect(errors_of(build(:resource, branch:, name: "   ").tap(&:valid?), :name)).to eq([ :blank ])
      expect(build(:resource, branch:, name: "a" * 120)).to be_valid
      expect(errors_of(build(:resource, branch:, name: "a" * 121).tap(&:valid?), :name)).to eq([ :too_long ])
    end
  end

  it "una sucursal de otra empresa es un error de campo (branch_id: invalid) y la FK compuesta lo impide en la base", :aggregate_failures do
    with_tenant(organization) do
      foreign_branch = create(:branch, company: other_company)
      resource = build(:resource, branch:, branch_id: foreign_branch.id)

      expect(resource).not_to be_valid
      expect(errors_of(resource, :branch_id)).to eq([ :invalid ])
      expect { savepoint { resource.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_resources_branch/)
    end
  end

  it "los archivados no entran en `unarchived` y los pausados no entran en `active`", :aggregate_failures do
    with_tenant(organization) do
      live = create(:resource, branch:)
      paused = create(:resource, branch:, active: false)
      archived = create(:resource, branch:, archived_at: Time.current)

      expect(described_class.unarchived.pluck(:id)).to contain_exactly(live.id, paused.id)
      expect(described_class.active.pluck(:id)).to eq([ live.id ])
      expect(archived).to be_archived
    end
  end
end
