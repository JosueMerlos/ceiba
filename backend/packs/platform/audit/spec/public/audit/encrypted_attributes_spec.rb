require "rails_helper"

# Encrypted PII with a REAL Active Record Encryption model: there is no encrypted PII in the product yet, so the probe
# declares `encrypts` on an organizations column inside the spec.
RSpec.describe "Audit.record con atributos cifrados (criterio 5)" do
  let(:organization) { create(:organization) }
  let(:probe_class) do
    Class.new(ApplicationRecord) do
      self.table_name = "organizations"
      encrypts :legal_name
    end
  end

  before do
    stub_const("ProbeOrganization", probe_class)
  end

  it "el diff de un campo cifrado muestra [FILTERED], no el valor" do
    probe = ProbeOrganization.find(organization.id)
    before_value = probe.legal_name
    probe.update!(legal_name: "Razón Social Secreta S.A.")

    with_tenant(organization) do
      Audit.record(action: "organization.updated", subject: probe,
        before: { "legal_name" => before_value, "name" => "A" }, after: { "legal_name" => probe.legal_name, "name" => "B" })
    end

    with_tenant(organization) do
      event = Audit::Event.last
      expect(event.after).to eq("legal_name" => "[FILTERED]", "name" => "B")
      expect(event.to_json).not_to include("Razón Social Secreta")
    end
  end

  it "cualquier campo sensible por nombre queda enmascarado aunque el modelo no lo declare, también anidado" do
    with_tenant(organization) do
      Audit.record(action: "x.updated", subject: organization, before: { "settings" => { "whatsapp_token" => "a" } }, after: { "settings" => { "whatsapp_token" => "b" } })
    end

    with_tenant(organization) { expect(Audit::Event.last.after).to eq("settings" => { "whatsapp_token" => "[FILTERED]" }) }
  end
end
