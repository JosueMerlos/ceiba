require "rails_helper"

RSpec.describe "Tenancy.with_context" do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }

  def db_setting
    ActiveRecord::Base.connection.select_value("SELECT current_setting('app.organization_id', true)")
  end

  it "requiere un bloque" do
    expect { Tenancy.with_context(organization:) }.to raise_error(ArgumentError, /bloque/)
  end

  it "devuelve el valor del bloque" do
    expect(Tenancy.with_context(organization:) { :resultado }).to eq(:resultado)
  end

  it "entrega el contexto al bloque" do
    Tenancy.with_context(organization:, company:, branch:) do |context|
      expect(context).to be_a(Tenancy::Context).and have_attributes(organization:, company:, branch:)
    end
  end

  describe "acts_as_tenant" do
    it "fija la organización como tenant dentro del bloque y la restaura al salir" do
      expect(ActsAsTenant.current_tenant).to be_nil

      Tenancy.with_context(organization:) { expect(ActsAsTenant.current_tenant).to eq(organization) }

      expect(ActsAsTenant.current_tenant).to be_nil
    end

    it "permite consultar tablas tenant dentro y las bloquea fuera" do
      Tenancy.with_context(organization:) { expect(Tenancy::Company.count).to eq(0) }

      expect { Tenancy::Company.count }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
    end

    it "restaura el tenant aunque el bloque lance" do
      expect { Tenancy.with_context(organization:) { raise "boom" } }.to raise_error("boom")

      expect(ActsAsTenant.current_tenant).to be_nil
    end

    it "aísla a la organización A de la B" do
      other = create(:organization)
      other_company = create_in(other, :company)

      Tenancy.with_context(organization:) do
        expect { Tenancy::Company.find(other_company.id) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "Current.context" do
    it "expone el contexto dentro del bloque y lo restaura al salir" do
      Tenancy.with_context(organization:, company:) do |context|
        expect(Current.context).to equal(context)
      end

      expect(Current.context).to be_nil
    end

    it "anida contextos y restaura el externo" do
      Tenancy.with_context(organization:) do |outer|
        Tenancy.with_context(organization:, company:) { expect(Current.context.company).to eq(company) }

        expect(Current.context).to equal(outer)
      end
    end
  end

  describe "coherencia (criterio 9)" do
    it "lanza InconsistentContext con una sucursal que no es de la empresa indicada" do
      other_branch = create_in(organization, :branch)

      expect { Tenancy.with_context(organization:, company:, branch: other_branch) { flunk } }
        .to raise_error(Tenancy::InconsistentContext)
    end

    it "no ejecuta el bloque ni toca la base si el contexto es incoherente" do
      foreign_company = create_in(create(:organization), :company)
      ran = false

      expect { Tenancy.with_context(organization:, company: foreign_company) { ran = true } }.to raise_error(Tenancy::InconsistentContext)
      expect(ran).to be(false)
      expect(db_setting).to be_blank
    end
  end

  describe "SET LOCAL app.organization_id" do
    it "fija el setting de PostgreSQL con el id de la organización dentro del bloque" do
      Tenancy.with_context(organization:) { expect(db_setting).to eq(organization.id) }
    end

    it "se ejecuta dentro de una transacción" do
      Tenancy.with_context(organization:) { expect(ActiveRecord::Base.connection.transaction_open?).to be(true) }
    end

    it "no se filtra fuera del bloque" do
      Tenancy.with_context(organization:) { db_setting }

      expect(db_setting).to be_blank
    end

    it "no se filtra fuera del bloque si este lanza" do
      expect { Tenancy.with_context(organization:) { raise "boom" } }.to raise_error("boom")

      expect(db_setting).to be_blank
    end

    it "no se filtra si el bloque falla con un error de base de datos" do
      expect do
        Tenancy.with_context(organization:) { ActiveRecord::Base.connection.execute("SELECT 1/0") }
      end.to raise_error(ActiveRecord::StatementInvalid)

      expect(db_setting).to be_blank
    end

    it "anidar organizaciones restaura la externa al salir de la interna" do
      other = create(:organization)

      Tenancy.with_context(organization:) do
        Tenancy.with_context(organization: other) { expect(db_setting).to eq(other.id) }

        expect(db_setting).to eq(organization.id)
      end
    end

    it "pasa el id como parámetro enlazado, nunca interpolado" do
      evil = "x'); DROP TABLE organizations; --"
      hostile = Tenancy::Organization.new(name: "hostil")
      allow(hostile).to receive_messages(persisted?: true, id: evil)
      statements = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] }

      Tenancy.with_context(organization: hostile) { expect(db_setting).to eq(evil) }

      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(statements.grep(/set_config/)).to all(include("set_config($1, $2, true)"))
      expect(statements.join).not_to include("DROP TABLE")
    end
  end

  describe "transacción" do
    it "revierte lo escrito dentro del bloque si este lanza" do
      expect do
        Tenancy.with_context(organization:) do
          create(:company)
          raise "boom"
        end
      end.to raise_error("boom")

      Tenancy.with_context(organization:) { expect(Tenancy::Company.count).to eq(0) }
    end
  end

  # Rails enables the query cache in requests and jobs: the setting is read and written WITHOUT cache, or an identical second
  # with_context would serve set_config from the cache and never run it.
  describe "con la query cache activa" do
    def real_setting
      ActiveRecord::Base.connection.uncached { db_setting }
    end

    it "fija el setting en cada with_context aunque se repita la misma organización" do
      seen = []
      ActiveRecord::Base.cache do
        2.times { Tenancy.with_context(organization:) { seen << real_setting } }
      end

      expect(seen).to eq([ organization.id, organization.id ])
    end

    it "al anidar B y luego A, el setting y el tenant coinciden dentro de cada bloque y se restauran al salir" do
      other = create(:organization)
      seen = []

      ActiveRecord::Base.cache do
        Tenancy.with_context(organization: other) do
          Tenancy.with_context(organization:) { seen << [ real_setting, ActsAsTenant.current_tenant.id ] }
          seen << [ real_setting, ActsAsTenant.current_tenant.id ]
        end
        seen << real_setting
      end

      expect(seen.first(2)).to eq([ [ organization.id, organization.id ], [ other.id, other.id ] ])
      expect(seen.last).to be_blank
    end
  end

  # return and break leave the block without an exception: the setting must be restored too.
  describe "salida no local del bloque" do
    def with_return(org)
      Tenancy.with_context(organization: org) { return :salio }
    end

    def with_break(org)
      [ 1 ].each { Tenancy.with_context(organization: org) { break } }
    end

    def nested_return(outer, inner)
      Tenancy.with_context(organization: outer) do
        with_return(inner)
        [ db_setting, ActsAsTenant.current_tenant.id ]
      end
    end

    it "return restaura el setting y el tenant" do
      expect(with_return(organization)).to eq(:salio)
      expect(db_setting).to be_blank
      expect(ActsAsTenant.current_tenant).to be_nil
    end

    it "break restaura el setting" do
      with_break(organization)

      expect(db_setting).to be_blank
    end

    it "un return interior no deja el setting de A bajo el tenant de B" do
      other = create(:organization)

      expect(nested_return(other, organization)).to eq([ other.id, other.id ])
    end
  end
end
