require "rails_helper"

RSpec.describe Appointments::Service do
  let(:organization) { create(:organization) }
  let(:nio_company) { create_in(organization, :company, currency: "NIO") }
  let(:usd_company) { create_in(organization, :company, currency: "USD") }

  def errors_of(service, attribute) = service.errors.where(attribute).map(&:type)

  describe "moneda" do
    it "un servicio en USD en una empresa con NIO es inválido (currency: mismatch)" do
      with_tenant(organization) do
        service = build(:service, company: nio_company, currency: "USD")

        expect(service).not_to be_valid
        expect(errors_of(service, :currency)).to eq([ :mismatch ])
      end
    end

    it "sin moneda toma la de la empresa" do
      with_tenant(organization) do
        nio = described_class.new(company_id: nio_company.id, name: "Corte", duration_minutes: 30, price_minor: 100)
        usd = described_class.new(company_id: usd_company.id, name: "Limpieza", duration_minutes: 30, price_minor: 100)

        expect([ nio, usd ].each(&:valid?).map(&:currency)).to eq(%w[NIO USD])
      end
    end

    it "una moneda que no es NIO ni USD es inválida" do
      with_tenant(organization) do
        service = build(:service, company: nio_company, currency: "EUR")

        expect(service).not_to be_valid
        expect(errors_of(service, :currency)).to include(:inclusion)
      end
    end

    it "una empresa que no existe en la organización activa no deja guardar el servicio (no se adivina la moneda)" do
      with_tenant(organization) do
        service = described_class.new(company_id: SecureRandom.uuid, name: "Corte", duration_minutes: 30, price_minor: 100)

        expect(service).not_to be_valid
        expect(errors_of(service, :company_id)).to eq([ :invalid ])
      end
    end
  end

  describe "precio" do
    it "un precio negativo es inválido y cero es válido (servicio gratuito)" do
      with_tenant(organization) do
        expect(build(:service, company: nio_company, price_minor: -1)).not_to be_valid
        expect(build(:service, company: nio_company, price_minor: 0)).to be_valid
      end
    end

    it "el precio debe ser un entero (nada de decimales)" do
      with_tenant(organization) do
        service = build(:service, company: nio_company, price_minor: 10.5)

        expect(service).not_to be_valid
        expect(errors_of(service, :price_minor)).to eq([ :not_an_integer ])
      end
    end
  end

  describe "tiempos" do
    it "la duración debe ser positiva y los buffers no pueden ser negativos", :aggregate_failures do
      with_tenant(organization) do
        expect(build(:service, company: nio_company, duration_minutes: 0)).not_to be_valid
        expect(build(:service, company: nio_company, buffer_before_minutes: -1)).not_to be_valid
        expect(build(:service, company: nio_company, buffer_after_minutes: -5)).not_to be_valid
        expect(build(:service, company: nio_company, buffer_before_minutes: 0, buffer_after_minutes: 10)).to be_valid
      end
    end

    it "un valor fuera del rango de la columna es un error de campo, no una excepción de la base (adversarial)", :aggregate_failures do
      with_tenant(organization) do
        too_long = build(:service, company: nio_company, duration_minutes: 2_147_483_648)
        too_expensive = build(:service, company: nio_company, price_minor: 10**30)

        expect(too_long).not_to be_valid
        expect(errors_of(too_long, :duration_minutes)).to eq([ :less_than_or_equal_to ])
        expect(too_expensive).not_to be_valid
        expect(errors_of(too_expensive, :price_minor)).to eq([ :less_than_or_equal_to ])
      end
    end

    it "el precio máximo es 2**53 - 1: un entero que el cliente TypeScript no pierde (adversarial)", :aggregate_failures do
      with_tenant(organization) do
        expect(build(:service, company: nio_company, price_minor: (2**53) - 1)).to be_valid
        over = build(:service, company: nio_company, price_minor: 2**53)

        expect(over).not_to be_valid
        expect(errors_of(over, :price_minor)).to eq([ :less_than_or_equal_to ])
      end
    end

    it "active no puede ser nulo (la columna es NOT NULL: sería un error de la base en vez de un error de campo)" do
      with_tenant(organization) do
        service = build(:service, company: nio_company, active: nil)

        expect(service).not_to be_valid
        expect(errors_of(service, :active)).to eq([ :inclusion ])
      end
    end

    it "el nombre es obligatorio y no puede ser solo espacios" do
      with_tenant(organization) do
        expect(build(:service, company: nio_company, name: "   ")).not_to be_valid
      end
    end
  end

  describe "scopes" do
    it "unarchived incluye los inactivos y excluye los archivados; active excluye además los inactivos", :aggregate_failures do
      with_tenant(organization) do
        live = create(:service, company: nio_company)
        paused = create(:service, company: nio_company, active: false)
        create(:service, company: nio_company, archived_at: Time.current)
        create(:service, company: nio_company, active: false, archived_at: Time.current)
        scoped = described_class.where(company_id: nio_company.id)

        expect(scoped.unarchived.pluck(:id)).to contain_exactly(live.id, paused.id)
        expect(scoped.active.pluck(:id)).to eq([ live.id ])
      end
    end
  end
end
