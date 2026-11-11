require "rails_helper"

RSpec.describe Appointments::TimeOff do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:professional) { create_in(organization, :professional, company:) }

  def errors_of(time_off, attribute) = time_off.errors.where(attribute).map(&:type)

  it "es una ausencia de un profesional o de un recurso, en UTC", :aggregate_failures do
    with_tenant(organization) do
      absence = create(:time_off, professional:, reason: "Vacaciones")
      closed = create(:time_off, resource: create(:resource, branch:))

      expect(absence.reload).to have_attributes(owner_type: "professional", professional_id: professional.id, resource_id: nil, company_id: company.id,
                                                starts_at: Time.utc(2026, 11, 16, 9), ends_at: Time.utc(2026, 11, 16, 13), reason: "Vacaciones")
      expect(closed.reload).to have_attributes(owner_type: "resource", professional_id: nil)
      expect(absence).to be_professional_owner
      expect(closed).to be_resource_owner
    end
  end

  context "con starts_at igual o posterior a ends_at" do
    it "es un error de modelo y un CHECK en la base de datos", :aggregate_failures do
      with_tenant(organization) do
        equal = build(:time_off, professional:, ends_at: Time.utc(2026, 11, 16, 9))
        reversed = build(:time_off, professional:, ends_at: Time.utc(2026, 11, 16, 8))

        expect([ equal, reversed ]).to all(satisfy { !it.valid? })
        expect(errors_of(equal, :ends_at)).to eq([ :invalid ])
        expect { savepoint { equal.save!(validate: false) } }.to raise_error(ActiveRecord::CheckViolation, /chk_time_offs_range/)
      end
    end
  end

  context "con ausencias que se solapan del mismo dueño" do
    it "están permitidas: el motor resta la unión", :aggregate_failures do
      with_tenant(organization) do
        create(:time_off, professional:)
        overlapping = build(:time_off, professional:, starts_at: Time.utc(2026, 11, 16, 11), ends_at: Time.utc(2026, 11, 16, 15))

        expect(overlapping).to be_valid
        expect { overlapping.save! }.to change(described_class, :count).by(1)
      end
    end
  end

  context "con un dueño incoherente" do
    it "profesional y recurso a la vez es inválido en el modelo y en la base (CHECK)", :aggregate_failures do
      with_tenant(organization) do
        absence = build(:time_off, professional:)
        absence.resource_id = create(:resource, branch:).id

        expect(absence).not_to be_valid
        expect { savepoint { absence.save!(validate: false) } }.to raise_error(ActiveRecord::CheckViolation, /chk_time_offs_owner/)
      end
    end

    it "sin ningún dueño es inválido en el modelo y en la base (CHECK)", :aggregate_failures do
      with_tenant(organization) do
        absence = build(:time_off, professional:)
        absence.professional_id = nil

        expect(absence).not_to be_valid
        expect { savepoint { absence.save!(validate: false) } }.to raise_error(ActiveRecord::CheckViolation, /chk_time_offs_owner/)
      end
    end

    it "una sucursal no tiene ausencias: el tipo de dueño es profesional o recurso (CHECK)", :aggregate_failures do
      with_tenant(organization) do
        absence = build(:time_off, professional:).tap { it.owner_type = "branch" }

        expect(absence).not_to be_valid
        expect { savepoint { absence.save!(validate: false) } }.to raise_error(ActiveRecord::CheckViolation, /chk_time_offs_owner/)
      end
    end

    it "el profesional de otra empresa es un error de campo y la FK compuesta lo impide", :aggregate_failures do
      with_tenant(organization) do
        foreign = create(:professional, company: create(:company))
        absence = build(:time_off, professional:, professional_id: foreign.id)

        expect(absence).not_to be_valid
        expect(errors_of(absence, :professional_id)).to eq([ :invalid ])
        expect { savepoint { absence.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_time_offs_professional/)
      end
    end

    it "el recurso de otra empresa es un error de campo y la FK compuesta lo impide", :aggregate_failures do
      with_tenant(organization) do
        foreign = create(:resource, branch: create(:branch, company: create(:company)))
        absence = build(:time_off, resource: create(:resource, branch:), resource_id: foreign.id)

        expect(absence).not_to be_valid
        expect(errors_of(absence, :resource_id)).to eq([ :invalid ])
        expect { savepoint { absence.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_time_offs_resource/)
      end
    end
  end

  describe "duración y motivo" do
    it "admite hasta 366 días", :aggregate_failures do
      with_tenant(organization) do
        start = Time.utc(2026, 1, 1)

        expect(build(:time_off, professional:, starts_at: start, ends_at: start + 366.days)).to be_valid
        too_long = build(:time_off, professional:, starts_at: start, ends_at: start + 366.days + 1.second)
        expect(too_long).not_to be_valid
        expect(errors_of(too_long, :ends_at)).to eq([ :invalid ])
      end
    end

    it "el motivo es opcional y admite hasta 200 caracteres (CHECK en la base)", :aggregate_failures do
      with_tenant(organization) do
        expect(build(:time_off, professional:, reason: nil)).to be_valid
        expect(build(:time_off, professional:, reason: "a" * 200)).to be_valid
        long = build(:time_off, professional:, reason: "a" * 201)
        expect(errors_of(long.tap(&:valid?), :reason)).to eq([ :too_long ])
        expect { savepoint { long.save!(validate: false) } }.to raise_error(ActiveRecord::CheckViolation, /chk_time_offs_reason/)
      end
    end
  end
end
