require "rails_helper"

# Active Record Encryption: the keys are NOT in the repository. In development and test they are derived from
# secret_key_base (key_generator, like the CSRF token); in production and staging they come from the environment and, if
# missing, encryption FAILS (closed) instead of using a default key.
RSpec.describe "Active Record Encryption: claves" do
  describe EncryptionKeys do
    let(:generator) { Rails.application.key_generator }

    it "fuera de producción deriva las tres claves de secret_key_base, distintas entre sí" do
      keys = described_class.for(production: false, env: {}, key_generator: generator)

      expect(keys.values).to all(match(/\A\h{32,}\z/))
      expect(keys.values.uniq.size).to eq(3)
      expect(keys.keys).to contain_exactly(:primary_key, :deterministic_key, :key_derivation_salt)
    end

    it "la derivación es estable (la misma secret_key_base da las mismas claves) y cambia con ella" do
      other = ActiveSupport::KeyGenerator.new("otra-secret-key-base", hash_digest_class: OpenSSL::Digest::SHA256)

      first = described_class.for(production: false, env: {}, key_generator: generator)

      expect(described_class.for(production: false, env: {}, key_generator: Rails.application.key_generator)).to eq(first)
      expect(described_class.for(production: false, env: {}, key_generator: other)).not_to eq(first)
    end

    it "en producción lee las claves del entorno" do
      env = { "AR_ENCRYPTION_PRIMARY_KEY" => "p" * 32, "AR_ENCRYPTION_DETERMINISTIC_KEY" => "d" * 32, "AR_ENCRYPTION_KEY_DERIVATION_SALT" => "s" * 32 }

      expect(described_class.for(production: true, env:, key_generator: generator))
        .to eq(primary_key: "p" * 32, deterministic_key: "d" * 32, key_derivation_salt: "s" * 32)
    end

    it "en producción SIN variables no inventa claves: quedan nil (el cifrado falla cerrado)" do
      expect(described_class.for(production: true, env: {}, key_generator: generator).values).to all(be_nil)
    end
  end

  it "la aplicación cifra en test sin configurar nada a mano" do
    probe = Class.new(ApplicationRecord) do
      self.table_name = "organizations"
      encrypts :legal_name
    end

    expect(probe.type_for_attribute(:legal_name).serialize("Razón Social")).not_to include("Razón Social")
  end
end
