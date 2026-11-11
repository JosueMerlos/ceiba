require "rails_helper"

RSpec.describe Appointments::ProfessionalBranchAssignment do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:other_company) { create_in(organization, :company) }
  let(:professional) { create_in(organization, :professional, company:) }
  let(:branch) { create_in(organization, :branch, company:) }

  def errors_of(assignment, attribute) = assignment.errors.where(attribute).map(&:type)

  it "asigna un profesional a una sucursal de su empresa" do
    with_tenant(organization) do
      assignment = create(:professional_branch_assignment, professional:, branch:)

      expect(assignment.reload).to have_attributes(professional_id: professional.id, branch_id: branch.id, company_id: company.id)
    end
  end

  it "una sucursal de otra empresa es un error de campo (branch_id: invalid) antes de llegar a la base de datos" do
    with_tenant(organization) do
      foreign_branch = create(:branch, company: other_company)
      assignment = build(:professional_branch_assignment, professional:, branch: foreign_branch)

      expect(assignment).not_to be_valid
      expect(errors_of(assignment, :branch_id)).to eq([ :invalid ])
    end
  end

  it "la base de datos rechaza la sucursal de otra empresa aunque se salte la validación: la FK compuesta" do
    with_tenant(organization) do
      foreign_branch = create(:branch, company: other_company)
      assignment = build(:professional_branch_assignment, professional:, branch: foreign_branch)

      expect { savepoint { assignment.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_pba_branch/)
    end
  end

  it "la base de datos rechaza un profesional de otra empresa aunque se salte la validación" do
    with_tenant(organization) do
      foreign_professional = create(:professional, company: other_company)
      assignment = build(:professional_branch_assignment, professional:, branch:, professional_id: foreign_professional.id)

      expect { savepoint { assignment.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_pba_professional/)
    end
  end

  it "un profesional de otra empresa es un error de campo (professional_id: invalid)" do
    with_tenant(organization) do
      foreign_professional = create(:professional, company: other_company)
      assignment = build(:professional_branch_assignment, professional:, branch:, professional_id: foreign_professional.id)

      expect(assignment).not_to be_valid
      expect(errors_of(assignment, :professional_id)).to eq([ :invalid ])
    end
  end

  it "asignar dos veces la misma sucursal es inválido (branch_id: taken)" do
    with_tenant(organization) do
      create(:professional_branch_assignment, professional:, branch:)
      duplicate = build(:professional_branch_assignment, professional:, branch:)

      expect(duplicate).not_to be_valid
      expect(errors_of(duplicate, :branch_id)).to eq([ :taken ])
    end
  end

  it "la base de datos también impide la asignación repetida" do
    with_tenant(organization) do
      create(:professional_branch_assignment, professional:, branch:)
      duplicate = build(:professional_branch_assignment, professional:, branch:)

      expect { savepoint { duplicate.save!(validate: false) } }.to raise_error(ActiveRecord::RecordNotUnique, /uq_pba_/)
    end
  end

  it "un profesional puede estar en varias sucursales y una sucursal tener varios profesionales" do
    with_tenant(organization) do
      create(:professional_branch_assignment, professional:, branch:)
      other_branch = create(:branch, company:)
      other_professional = create(:professional, company:)

      expect(build(:professional_branch_assignment, professional:, branch: other_branch)).to be_valid
      expect(build(:professional_branch_assignment, professional: other_professional, branch:)).to be_valid
    end
  end

  it "un profesional archivado no admite asignaciones nuevas (base: archived)" do
    with_tenant(organization) do
      archived = create(:professional, company:, archived_at: Time.current)
      assignment = build(:professional_branch_assignment, professional: archived, branch:)

      expect(assignment).not_to be_valid
      expect(errors_of(assignment, :base)).to eq([ :archived ])
    end
  end
end
