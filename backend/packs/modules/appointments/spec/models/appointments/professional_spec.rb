require "rails_helper"

RSpec.describe Appointments::Professional do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:other_company) { create_in(organization, :company) }
  let(:person) { create(:user) }

  def errors_of(professional, attribute) = professional.errors.where(attribute).map(&:type)

  context "con la misma persona en dos empresas del grupo" do
    it "permite un registro por empresa, cada uno con su identidad propia", :aggregate_failures do
      user_with_role("receptionist", organization, branch: create_in(organization, :branch, company:), user: person)

      with_tenant(organization) do
        first = create(:professional, company:, user_id: person.id, display_name: "Sandra en la clínica")
        second = create(:professional, company: other_company, user_id: person.id, display_name: "Sandra en el salón")

        expect(first.reload).to have_attributes(company_id: company.id, user_id: person.id)
        expect(second.reload).to have_attributes(company_id: other_company.id, user_id: person.id)
        expect(described_class.where(company_id: company.id).pluck(:id)).to eq([ first.id ])
        expect(described_class.where(company_id: other_company.id).pluck(:id)).to eq([ second.id ])
      end
    end
  end

  context "con un user_id que no es un UUID" do
    it "es user_id: invalid en vez de convertirse en nil (desvincular es solo null explícito)", :aggregate_failures do
      with_tenant(organization) do
        malformed = build(:professional, company:, user_id: "no-es-un-uuid")

        expect(malformed).not_to be_valid
        expect(errors_of(malformed, :user_id)).to eq([ :invalid ])
        expect(build(:professional, company:, user_id: nil)).to be_valid
      end
    end
  end

  context "con un user_id ya fijado" do
    it "no cambia a otra persona ni a null (user_id: immutable) y reenviar el mismo no es un cambio", :aggregate_failures do
      other = create(:user)
      user_with_role("receptionist", organization, branch: create_in(organization, :branch, company:), user: person)
      user_with_role("receptionist", organization, branch: create_in(organization, :branch, company:), user: other)

      with_tenant(organization) do
        linked = create(:professional, company:, user_id: person.id)

        [ other.id, nil, "no-es-un-uuid" ].each do |change|
          linked.user_id = change
          expect(linked).not_to be_valid
          expect(errors_of(linked, :user_id)).to eq([ :immutable ])
        end
        linked.user_id = person.id
        expect(linked).to be_valid
      end
    end

    it "uno sin vincular se puede vincular una vez" do
      user_with_role("receptionist", organization, branch: create_in(organization, :branch, company:), user: person)

      with_tenant(organization) do
        unlinked = create(:professional, company:, user_id: nil)
        unlinked.user_id = person.id

        expect(unlinked).to be_valid
      end
    end
  end

  context "con la misma persona dos veces en la misma empresa" do
    it "rechaza el segundo registro con user_id: taken" do
      user_with_role("receptionist", organization, branch: create_in(organization, :branch, company:), user: person)

      with_tenant(organization) do
        create(:professional, company:, user_id: person.id)
        duplicate = build(:professional, company:, user_id: person.id)

        expect(duplicate).not_to be_valid
        expect(errors_of(duplicate, :user_id)).to eq([ :taken ])
      end
    end

    it "la base de datos también lo impide aunque se salte la validación" do
      user_with_role("receptionist", organization, branch: create_in(organization, :branch, company:), user: person)

      with_tenant(organization) do
        create(:professional, company:, user_id: person.id)
        duplicate = build(:professional, company:, user_id: person.id)

        expect { savepoint { duplicate.save!(validate: false) } }.to raise_error(ActiveRecord::RecordNotUnique, /uq_professionals_company_user/)
      end
    end

    it "un registro archivado libera a la persona: se puede crear otro con el mismo usuario, también en la base", :aggregate_failures do
      user_with_role("receptionist", organization, branch: create_in(organization, :branch, company:), user: person)

      with_tenant(organization) do
        create(:professional, company:, user_id: person.id, archived_at: Time.current)
        relinked = build(:professional, company:, user_id: person.id)

        expect(relinked).to be_valid
        expect { savepoint { relinked.save!(validate: false) } }.not_to raise_error
      end
    end
  end

  context "con un user_id sin membresía en la organización" do
    it "es inválido (user_id: invalid)" do
      with_tenant(organization) do
        professional = build(:professional, company:, user_id: create(:user).id)

        expect(professional).not_to be_valid
        expect(errors_of(professional, :user_id)).to eq([ :invalid ])
      end
    end

    it "quien es miembro solo de OTRA organización tampoco vale" do
      user_with_role("org_admin", create(:organization), user: person)

      with_tenant(organization) { expect(build(:professional, company:, user_id: person.id)).not_to be_valid }
    end
  end

  context "sin persona vinculada" do
    it "es válido y varios profesionales de la empresa pueden no tener user_id" do
      with_tenant(organization) do
        create(:professional, company:)

        expect(build(:professional, company:, user_id: nil)).to be_valid
      end
    end
  end

  describe "nombre" do
    it "es obligatorio, se recorta y admite hasta 120 caracteres", :aggregate_failures do
      with_tenant(organization) do
        blank = build(:professional, company:, display_name: "   ")
        too_long = build(:professional, company:, display_name: "a" * 121)
        padded = build(:professional, company:, display_name: "  Ana  ")

        expect(blank).not_to be_valid
        expect(too_long).not_to be_valid
        expect(errors_of(blank, :display_name)).to eq([ :blank ])
        expect(errors_of(too_long, :display_name)).to eq([ :too_long ])
        expect(padded).to be_valid
        expect(padded.display_name).to eq("Ana")
        expect(build(:professional, company:, display_name: "a" * 120)).to be_valid
      end
    end

    it "la base de datos rechaza un nombre en blanco aunque se salte la validación" do
      with_tenant(organization) do
        professional = build(:professional, company:, display_name: "  ")

        expect { savepoint { professional.save!(validate: false) } }.to raise_error(ActiveRecord::StatementInvalid, /chk_professionals_name_present/)
      end
    end
  end

  describe "empresa" do
    it "una empresa inexistente es un error de campo (company_id)" do
      with_tenant(organization) do
        professional = build(:professional, company:, company_id: SecureRandom.uuid)

        expect(professional).not_to be_valid
        expect(errors_of(professional, :company_id)).to eq([ :invalid ])
      end
    end
  end

  describe "scopes" do
    it "unarchived deja fuera los archivados y active además los pausados" do
      with_tenant(organization) do
        live = create(:professional, company:)
        paused = create(:professional, company:, active: false)
        archived = create(:professional, company:, archived_at: Time.current)

        expect(described_class.unarchived).to contain_exactly(live, paused)
        expect(described_class.active).to contain_exactly(live)
        expect(archived).to be_archived
      end
    end
  end
end
