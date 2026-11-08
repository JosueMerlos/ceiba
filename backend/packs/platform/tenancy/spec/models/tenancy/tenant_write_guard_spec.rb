require "rails_helper"

RSpec.describe Tenancy::TenantWriteGuard do
  let(:organization) { create(:organization) }
  let(:other) { create(:organization) }

  # Modelo sonda sobre la tabla real companies: un before_save DECLARADO DESPUÉS de acts_as_tenant que cambia el tenant.
  let(:sneaky_model) do
    target = other
    Class.new(ApplicationRecord) do
      self.table_name = "companies"
      def self.name = "SneakyCompany"
      acts_as_tenant :organization, class_name: "Tenancy::Organization"
      before_save { self[:organization_id] = target.id }
    end
  end

  def probe_attributes(slug) = { name: "Sonda", slug:, business_type: "salon", currency: "NIO" }

  it "ApplicationRecord (pack raíz) no referencia a tenancy: el pack engancha el guard por su cuenta" do
    expect(Rails.root.join("app/models/application_record.rb").read).not_to include('Tenancy')
  end

  it "se incluye en todo modelo que declara acts_as_tenant, sin hacer nada más" do
    expect(sneaky_model).to include(described_class)
  end

  it "ve el organization_id FINAL: un before_save del modelo declarado después no puede escapar al guard" do
    with_tenant(organization) do
      expect { sneaky_model.new(probe_attributes("sonda-1")).save!(validate: false) }.to raise_error(Tenancy::TenantMismatch)
    end
  end

  it "un before_update que cambia el organization_id tampoco escapa" do
    record = with_tenant(organization) { create(:company) }
    target = other
    klass = Class.new(ApplicationRecord) do
      self.table_name = "companies"
      def self.name = "SneakyUpdate"
      acts_as_tenant :organization, class_name: "Tenancy::Organization"
      before_update { self[:organization_id] = target.id }
    end

    with_tenant(organization) do
      loaded = klass.find(record.id)
      loaded.name = "cambiado"

      expect { loaded.save!(validate: false) }.to raise_error(Tenancy::TenantIsImmutable)
    end
  end

  describe "escrituras que no pasan por save" do
    it "update_columns con organization_id lanza TenantIsImmutable" do
      record = with_tenant(organization) { create(:company) }

      with_tenant(organization) do
        expect { Tenancy::Company.find(record.id).update_columns(organization_id: other.id) }.to raise_error(Tenancy::TenantIsImmutable)
      end
    end

    it "update_column con organization_id lanza TenantIsImmutable" do
      record = with_tenant(organization) { create(:company) }

      with_tenant(organization) do
        expect { Tenancy::Company.find(record.id).update_column(:organization_id, other.id) }.to raise_error(Tenancy::TenantIsImmutable)
      end
    end

    it "update_columns de otros atributos sigue funcionando" do
      record = with_tenant(organization) { create(:company) }

      with_tenant(organization) do
        expect(Tenancy::Company.find(record.id).update_columns(name: "Nuevo")).to be(true)
      end
    end

    it "update_all con organization_id (hash o SQL) lanza TenantIsImmutable" do
      with_tenant(organization) do
        expect { Tenancy::Company.update_all(organization_id: other.id) }.to raise_error(Tenancy::TenantIsImmutable)
        expect { Tenancy::Company.where(status: "active").update_all("organization_id = '#{other.id}'") }.to raise_error(Tenancy::TenantIsImmutable)
      end
    end

    it "update_all de otros atributos sigue funcionando y se limita al tenant" do
      mine = with_tenant(organization) { create(:company) }
      theirs = with_tenant(other) { create(:company) }

      with_tenant(organization) { Tenancy::Company.update_all(name: "Masivo") }

      expect(with_tenant(other) { Tenancy::Company.find(theirs.id).name }).not_to eq("Masivo")
      expect(with_tenant(organization) { Tenancy::Company.find(mine.id).name }).to eq("Masivo")
    end
  end

  # Canario: el guard depende de métodos privados de Active Record (_insert_record, _update_record...). Si una actualización
  # de Rails los renombra, el guard dejaría de ejecutarse EN SILENCIO: este spec falla antes.
  describe "canario de internos de Rails" do
    it "el guard es dueño de los métodos de clase que sobrescribe y estos tienen super" do
      %i[_insert_record _update_record _delete_record].each do |name|
        method = Tenancy::Company.method(name)

        expect(method.owner).to eq(Tenancy::TenantWriteGuard::ClassMethods), "#{name} no es del guard"
        expect(method.super_method).to be_present, "#{name} ya no existe en Active Record"
      end
    end

    it "el guard es dueño de los métodos de instancia que sobrescribe y estos tienen super" do
      %i[_update_row _delete_row update_columns].each do |name|
        method = Tenancy::Company.instance_method(name)

        expect(method.owner).to eq(Tenancy::TenantWriteGuard), "#{name} no es del guard"
        expect(method.super_method).to be_present, "#{name} ya no existe en Active Record"
      end
    end

    it "el instalador es dueño de acts_as_tenant y de las escrituras masivas de la relación" do
      expect(ActiveRecord::Base.method(:acts_as_tenant).owner).to eq(TenantGuardInstaller::ModelMethods)
      %i[insert_all insert_all! upsert_all update_all].each do |name|
        expect(Tenancy::Company.all.method(name).owner).to eq(TenantGuardInstaller::RelationMethods)
        expect(Tenancy::Company.all.method(name).super_method).to be_present
      end
    end

    it "los métodos de Rails que invocan los internos siguen llamándolos (touch y update_columns pasan por ellos)" do
      company = with_tenant(organization) { create(:company) }
      calls = []
      allow(Tenancy::Company).to receive(:_update_record).and_wrap_original { |original, *args| calls << :update && original.call(*args) }

      with_tenant(organization) do
        Tenancy::Company.find(company.id).tap(&:touch).update_columns(name: "x")
      end

      expect(calls.size).to eq(2)
    end
  end
end
