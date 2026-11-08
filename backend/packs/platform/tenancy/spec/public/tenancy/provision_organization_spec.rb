require "rails_helper"

RSpec.describe Tenancy::ProvisionOrganization do
  let(:params) do
    {
      organization: { name: "Barbería El Güegüense", legal_name: "El Güegüense, S.A." },
      company: { name: "Barbería El Güegüense", slug: "el-guegu", business_type: "barbershop", currency: "NIO" },
      branch: { name: "Sucursal Centro", time_zone: "America/Managua" }
    }
  end
  let(:hooks) { [] }

  after { hooks.each { |hook| described_class.remove_after_provision(hook) } }

  def register_hook(&block)
    described_class.after_provision(block).tap { |hook| hooks << hook }
  end

  def provision(**overrides) = described_class.call(**params.merge(overrides))

  def deep_params(section, **attrs) = { section => params.fetch(section).merge(attrs) }

  describe "caso feliz (criterio 5)" do
    it "crea organización, empresa y sucursal conectadas entre sí" do
      result = provision

      expect(result.organization).to be_persisted.and have_attributes(name: "Barbería El Güegüense", legal_name: "El Güegüense, S.A.", country_code: "NI")
      expect(result.company).to have_attributes(organization_id: result.organization.id, slug: "el-guegu", currency: "NIO")
      expect(result.branch).to have_attributes(organization_id: result.organization.id, company_id: result.company.id, time_zone: "America/Managua")
    end

    it "deja los registros visibles dentro del tenant de la organización" do
      result = provision

      Tenancy.with_context(organization: result.organization) do
        expect(Tenancy::Company.pluck(:slug)).to eq([ "el-guegu" ])
        expect(Tenancy::Branch.count).to eq(1)
      end
    end

    it "usa la zona America/Managua si no se indica" do
      result = provision(branch: { name: "Centro" })

      expect(result.branch.time_zone).to eq("America/Managua")
    end

    it "rechaza claves desconocidas en lugar de ignorarlas" do
      expect { provision(company: params[:company].merge(organization_id: SecureRandom.uuid)) }.to raise_error(ArgumentError, /organization_id/)
    end
  end

  describe "hooks after_provision" do
    it "ejecuta los hooks registrados, en orden, con el resultado" do
      calls = []
      register_hook { |result| calls << [ :primero, result.company.slug ] }
      register_hook { |result| calls << [ :segundo, result.branch.name ] }

      provision

      expect(calls).to eq([ [ :primero, "el-guegu" ], [ :segundo, "Sucursal Centro" ] ])
    end

    it "los ejecuta dentro del contexto de la nueva organización y de la transacción" do
      seen = nil
      register_hook do |result|
        seen = { context: Current.context, tenant: ActsAsTenant.current_tenant, setting: ApplicationRecord.connection.select_value("SELECT current_setting('app.organization_id', true)") }
        expect(result.organization).to be_persisted
      end

      result = provision

      expect(seen[:context]).to have_attributes(organization: result.organization, company: result.company, branch: result.branch)
      expect(seen).to include(tenant: result.organization, setting: result.organization.id)
    end

    it "acepta cualquier objeto que responda a call" do
      callable = Class.new { attr_reader :received; def call(result) = (@received = result) }.new
      hooks << described_class.after_provision(callable)

      result = provision

      expect(callable.received).to eq(result)
    end

    it "no ejecuta los hooks si falla la provisión" do
      called = false
      register_hook { called = true }

      expect { provision(company: params[:company].merge(slug: "admin")) }.to raise_error(Tenancy::ProvisioningFailed)
      expect(called).to be(false)
    end

    it "un hook que falla revierte TODO y propaga su error" do
      register_hook { |_| raise "hook roto" }

      expect { provision }.to raise_error("hook roto")
      expect(Tenancy::Organization.where(name: "Barbería El Güegüense")).to be_empty
    end

    it "dejar de registrar un hook lo quita de la lista" do
      called = false
      hook = register_hook { called = true }
      described_class.remove_after_provision(hook)

      provision

      expect(called).to be(false)
    end

    it "exige algo invocable" do
      expect { described_class.after_provision(:no_invocable) }.to raise_error(ArgumentError, /call/)
    end
  end

  describe "atomicidad (criterio 6)" do
    it "si falla la sucursal no queda ninguna organización ni empresa" do
      expect { provision(branch: { name: "Centro", time_zone: "Managua" }) }
        .to raise_error(Tenancy::ProvisioningFailed) { |error| expect(error.code).to eq(:invalid) }

      expect(Tenancy::Organization.where(name: "Barbería El Güegüense")).to be_empty
    end

    it "tampoco queda la empresa" do
      expect { provision(branch: { name: "Centro", time_zone: "Managua" }) }.to raise_error(Tenancy::ProvisioningFailed)

      expect(Tenancy::Company.unscoped.where(slug: "el-guegu")).to be_empty
    end

    it "el error de dominio indica la sección y el campo" do
      expect { provision(branch: { name: "Centro", time_zone: "Managua" }) }
        .to raise_error(Tenancy::ProvisioningFailed) { |error| expect(error.details).to include(branch: { time_zone: [ a_string_matching(/IANA/) ] }) }
    end

    it "no deja la transacción del llamador abortada: puede seguir usando la conexión" do
      expect { provision(company: params[:company].merge(slug: "admin")) }.to raise_error(Tenancy::ProvisioningFailed)

      expect(provision.company.slug).to eq("el-guegu")
    end
  end

  describe "slug (criterio 7)" do
    it "un slug reservado produce un error de dominio legible, no una excepción de BD" do
      expect { provision(company: params[:company].merge(slug: "admin")) }.to raise_error(Tenancy::ProvisioningFailed) do |error|
        expect(error).to be_a(Tenancy::Error).and have_attributes(code: :slug_reserved)
        expect(error.message).to match(/admin.*reservado/)
      end
    end

    it "un slug ya usado produce un error de dominio legible" do
      provision

      expect { provision(organization: { name: "Otra" }) }.to raise_error(Tenancy::ProvisioningFailed) do |error|
        expect(error).to have_attributes(code: :slug_taken)
        expect(error.message).to match(/el-guegu.*en uso/)
      end
    end

    it "un slug repetido no deja una segunda organización" do
      provision

      expect { provision(organization: { name: "Duplicada" }) }.to raise_error(Tenancy::ProvisioningFailed)
      expect(Tenancy::Organization.where(name: "Duplicada")).to be_empty
    end

    it "normaliza el slug antes de comprobar reservados" do
      expect { provision(company: params[:company].merge(slug: " ADMIN ")) }.to raise_error(Tenancy::ProvisioningFailed) { |e| expect(e.code).to eq(:slug_reserved) }
    end

    it "un formato inválido es un error :invalid, no :slug_taken" do
      expect { provision(company: params[:company].merge(slug: "no valido!")) }.to raise_error(Tenancy::ProvisioningFailed) { |e| expect(e.code).to eq(:invalid) }
    end
  end
end
