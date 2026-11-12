require "rails_helper"

# Tenancy::PublicDirectory: the one reader that finds a company by its public slug WITHOUT a tenant (an anonymous visitor
# has no organization yet). It returns the company and its organization, readonly, and nothing else.
RSpec.describe Tenancy::PublicDirectory do
  let(:organization) { create(:organization) }
  let!(:company) { create_in(organization, :company, slug: "barberia-central") }
  let!(:other_company) { create_in(create(:organization), :company, slug: "otra-barberia") }

  describe ".company_by_slug" do
    it "devuelve la empresa y su organización" do
      found = described_class.company_by_slug("barberia-central")

      expect(found).to eq(organization:, company:)
    end

    it "encuentra la empresa de cualquier organización, sin contexto previo" do
      expect(described_class.company_by_slug("otra-barberia")).to include(company: other_company)
    end

    it "normaliza el slug como la empresa: espacios y mayúsculas" do
      expect(described_class.company_by_slug("  Barberia-Central ")).to eq(organization:, company:)
    end

    it "devuelve nil si la organización está suspendida: no se opera bajo ella, tampoco de forma anónima" do
      organization.update!(status: "suspended")

      expect(described_class.company_by_slug("barberia-central")).to be_nil
    end

    it "devuelve nil si no existe" do
      expect(described_class.company_by_slug("no-existe")).to be_nil
    end

    it "devuelve nil para un slug reservado o con un formato que no puede existir, sin consultar" do
      queries = []
      counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }

      result = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        [ "api", "ab", "con espacio", "x" * 41, "", nil, 7 ].map { described_class.company_by_slug(it) }
      end

      expect(result).to all(be_nil)
      expect(queries).to be_empty
    end

    it "no trata el slug como un patrón" do
      expect(described_class.company_by_slug("barberia-%")).to be_nil
    end

    it "devuelve registros de solo lectura" do
      found = described_class.company_by_slug("barberia-central")

      expect(found[:company]).to be_readonly
      expect(found[:organization]).to be_readonly
      expect { found[:company].update!(name: "x") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "no deja un tenant puesto al terminar" do
      described_class.company_by_slug("barberia-central")

      expect(ActsAsTenant.current_tenant).to be_nil
    end
  end

  it "no expone nada más que la búsqueda por slug" do
    expect(described_class.singleton_methods(false)).to contain_exactly(:company_by_slug)
  end
end
