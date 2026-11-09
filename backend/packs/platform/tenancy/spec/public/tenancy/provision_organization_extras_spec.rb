require "rails_helper"

# `extras:` lleva a los hooks after_provision datos que Tenancy NO interpreta (el dueño de la organización lo usa access,
# M0.08; los módulos por defecto, M0.09). Así el servicio no conoce a ningún otro pack y su contrato sigue igual: sin
# extras todo se comporta como antes.
RSpec.describe Tenancy::ProvisionOrganization, ".call con extras" do
  let(:params) do
    {
      organization: { name: "Extras S.A." },
      company: { name: "Extras", slug: "extras-spec", business_type: "salon", currency: "NIO" },
      branch: { name: "Centro", time_zone: "America/Managua" }
    }
  end
  let(:hooks) { [] }

  after { hooks.each { |hook| described_class.remove_after_provision(hook) } }

  def register_hook(&block) = described_class.after_provision(block).tap { |hook| hooks << hook }

  it "los hooks reciben los extras en result.extras, sin que el servicio los interprete" do
    seen = nil
    register_hook { |result| seen = result.extras }

    described_class.call(**params, extras: { owner: { id: "abc" }, plan: "pilot" })

    expect(seen).to eq(owner: { id: "abc" }, plan: "pilot")
  end

  it "sin extras, result.extras es un hash vacío y el Result conserva su forma" do
    result = described_class.call(**params)

    expect(result.extras).to eq({})
    expect(result).to have_attributes(organization: be_persisted, company: be_persisted, branch: be_persisted)
  end

  it "los extras son inmutables para el hook (no pueden alterar lo que ven los siguientes)" do
    register_hook { |result| result.extras[:otro] = 1 }

    expect { described_class.call(**params, extras: { a: 1 }) }.to raise_error(FrozenError)
  end

  it "extras debe ser un Hash" do
    expect { described_class.call(**params, extras: "dueño") }.to raise_error(ArgumentError, /extras/)
  end
end
