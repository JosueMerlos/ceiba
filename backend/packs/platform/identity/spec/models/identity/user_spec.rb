require "rails_helper"

# Criterio de tarea 1 de M0.07: normalización del correo y longitud de la contraseña. User es GLOBAL (no tenant,
# ADR-0028): no lleva organization_id.
RSpec.describe Identity::User do
  describe "correo" do
    it "se normaliza: sin espacios y en minúsculas" do
      user = create(:user, email: "  Ana.Perez@Ceiba.TEST ")

      expect(user.reload.email).to eq("ana.perez@ceiba.test")
    end

    it "es único sin distinguir mayúsculas (citext)" do
      create(:user, email: "ana@ceiba.test")

      duplicate = build(:user, email: "ANA@ceiba.test")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.details[:email]).to include(a_hash_including(error: :taken))
    end

    it "la base también lo garantiza (índice único sobre citext)" do
      create(:user, email: "ana@ceiba.test")
      other = build(:user, email: "otra@ceiba.test")
      other.save!

      expect { other.update_column(:email, "ANA@ceiba.test") }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "es obligatorio y con formato de correo" do
      expect(build(:user, email: "")).not_to be_valid
      expect(build(:user, email: "sin-arroba")).not_to be_valid
    end

    it "se busca sin importar mayúsculas ni espacios" do
      user = create(:user, email: "ana@ceiba.test")

      expect(described_class.find_by(email: " ANA@ceiba.test ")).to eq(user)
    end
  end

  describe "contraseña" do
    it "exige al menos 12 caracteres" do
      user = build(:user, password: "a" * 11)

      expect(user).not_to be_valid
      expect(user.errors.details[:password]).to include(a_hash_including(error: :too_short, count: 12))
    end

    it "acepta 12 caracteres sin reglas de complejidad" do
      expect(build(:user, password: "a" * 12)).to be_valid
    end

    it "se guarda como digest bcrypt, nunca en claro" do
      user = create(:user, password: "contraseña-segura-1")

      expect(user.password_digest).to start_with("$2a$")
      expect(user.password_digest).not_to include("contraseña")
    end

    it "es obligatoria al crear" do
      expect(build(:user, password: nil)).not_to be_valid
    end

    it "no se exige al actualizar otros datos" do
      user = create(:user)

      expect(described_class.find(user.id).update(full_name: "Ana María")).to be(true)
    end

    it "permite autenticar con la contraseña correcta y rechaza la incorrecta" do
      user = create(:user, password: "contraseña-segura-1")

      expect(user.authenticate("contraseña-segura-1")).to eq(user)
      expect(user.authenticate("otra-contraseña-12")).to be(false)
    end
  end

  it "exige el nombre completo" do
    expect(build(:user, full_name: " ")).not_to be_valid
  end

  it "es global: no es una tabla tenant" do
    expect(described_class.column_names).not_to include("organization_id")
    expect(Database::TenantTables.names).not_to include("users")
  end
end
