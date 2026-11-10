require "rails_helper"

# Audit.record: records who did what, with before and after, inside an organization's context.
RSpec.describe "Audit.record" do
  let(:organization) { create(:organization) }
  let(:principal) { Identity::Principal::User.new(id: SecureRandom.uuid, email: "ana@ceiba.test", full_name: "Ana") }

  def events = Audit::Event.order(:id).to_a

  it "sin contexto de tenancy lanza Audit::NoContext y no escribe nada" do
    expect { Audit.record(action: "organization.updated", subject: organization) }.to raise_error(Audit::NoContext)
  end

  it "Audit::NoContext es un Audit::Error" do
    expect(Audit::NoContext.ancestors).to include(Audit::Error)
  end

  it "registra la acción, el sujeto y la organización del contexto" do
    with_tenant(organization) { Audit.record(action: "organization.updated", subject: organization) }

    with_tenant(organization) do
      expect(events).to contain_exactly(
        have_attributes(organization_id: organization.id, action: "organization.updated", auditable_type: "Tenancy::Organization", auditable_id: organization.id)
      )
    end
  end

  it "toma el actor de Current.principal (tipo y id)" do
    Current.set(principal:) { with_tenant(organization) { Audit.record(action: "x.created", subject: organization) } }

    with_tenant(organization) { expect(events.first).to have_attributes(actor_type: "user", actor_id: principal.id) }
  end

  it "toma el actor del principal del contexto si Current no lo tiene" do
    Tenancy.with_context(organization:, principal:) { Audit.record(action: "x.created", subject: organization) }

    with_tenant(organization) { expect(events.first).to have_attributes(actor_type: "user", actor_id: principal.id) }
  end

  it "sin principal el actor es el sistema (jobs, seeds, consola), sin id" do
    with_tenant(organization) { Audit.record(action: "x.created", subject: organization) }

    with_tenant(organization) { expect(events.first).to have_attributes(actor_type: "system", actor_id: nil) }
  end

  it "acepta un actor explícito" do
    actor = Struct.new(:id, :actor_type).new(SecureRandom.uuid, "platform_staff")
    with_tenant(organization) { Audit.record(action: "x.created", subject: organization, actor:) }

    with_tenant(organization) { expect(events.first).to have_attributes(actor_type: "platform_staff", actor_id: actor.id) }
  end

  it "guarda request_id, IP y user agent de la request (Current)" do
    Current.set(request_id: "req-123", ip: "203.0.113.7", user_agent: "Mozilla/5.0") do
      with_tenant(organization) { Audit.record(action: "x.created", subject: organization) }
    end

    with_tenant(organization) do
      expect(events.first).to have_attributes(request_id: "req-123", ip: IPAddr.new("203.0.113.7"), user_agent: "Mozilla/5.0")
    end
  end

  it "guarda before, after y metadata" do
    with_tenant(organization) do
      Audit.record(action: "organization.updated", subject: organization, before: { "name" => "A", "status" => "active" },
        after: { "name" => "B", "status" => "active" }, metadata: { "reason" => "rename" })
    end

    with_tenant(organization) do
      expect(events.first).to have_attributes(before: { "name" => "A" }, after: { "name" => "B" }, metadata: { "reason" => "rename" })
    end
  end

  it "en una creación (sin before) guarda todos los atributos en after y before queda NULL" do
    with_tenant(organization) { Audit.record(action: "x.created", subject: organization, after: { "name" => "Nueva" }) }

    with_tenant(organization) { expect(events.first).to have_attributes(before: nil, after: { "name" => "Nueva" }) }
  end

  it "forma parte de la transacción del llamador: un rollback no deja evento" do
    with_tenant(organization) do
      savepoint do
        Audit.record(action: "x.created", subject: organization)
        raise ActiveRecord::Rollback
      end

      expect(events).to be_empty
    end
  end

  it "el evento no se puede modificar ni borrar desde el modelo" do
    with_tenant(organization) do
      Audit.record(action: "x.created", subject: organization)

      expect { events.first.update!(action: "otra") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { events.first.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  it "las consultas respetan el tenant: otra organización no ve los eventos" do
    other = create(:organization)
    with_tenant(organization) { Audit.record(action: "x.created", subject: organization) }

    with_tenant(other) { expect(events).to be_empty }
  end

  it "exige acción y sujeto" do
    with_tenant(organization) do
      expect { Audit.record(action: "", subject: organization) }.to raise_error(ArgumentError, /action/)
      expect { Audit.record(action: "x.y", subject: nil) }.to raise_error(ArgumentError, /subject/)
      expect { Audit.record(action: "x.y", subject: Tenancy::Organization.new) }.to raise_error(ArgumentError, /subject/)
    end
  end
end
