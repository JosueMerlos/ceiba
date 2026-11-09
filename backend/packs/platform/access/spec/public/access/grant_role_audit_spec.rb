require "rails_helper"

# Auditoría de los cambios de memberships (M0.11): Access::GrantRole es el único camino que escribe memberships hoy
# (seeds, OwnerHook, y las invitaciones de M4.01). Registra membership.granted en la MISMA transacción.
RSpec.describe "Auditoría de memberships (Access::GrantRole)" do
  let!(:world) { build_access_world }
  let(:organization) { world.organization }
  let!(:user) { Identity::ProvisionUser.call(email: "ana@ceiba.test", full_name: "Ana", password: "contraseña-segura-1") }

  def events = with_tenant(organization) { Audit::Event.where("action LIKE 'membership.%'").order(:id).to_a }

  it "audita membership.granted con el membership como sujeto y el alcance en after" do
    Access::GrantRole.call(user:, role_key: "company_manager", organization:, company: world.company_a)

    membership = with_tenant(organization) { Access::Membership.find_by!(user_id: user.id) }
    expect(events).to contain_exactly(
      have_attributes(
        action: "membership.granted", auditable_type: "Access::Membership", auditable_id: membership.id, before: nil,
        after: a_hash_including("user_id" => user.id, "role" => "company_manager", "scope_level" => "company", "company_id" => world.company_a.id, "branch_id" => nil)
      )
    )
  end

  it "no enmascara el rol (el nombre del campo no coincide con filter_parameters)" do
    Access::GrantRole.call(user:, role_key: "org_admin", organization:)

    expect(events.first.after["role"]).to eq("org_admin")
  end

  it "es idempotente también en la auditoría: repetir la concesión no deja un segundo evento" do
    2.times { Access::GrantRole.call(user:, role_key: "branch_manager", organization:, branch: world.branch_a1) }

    expect(events.size).to eq(1)
  end

  it "el actor es el principal de la request, o el sistema si no hay" do
    operator = Access::Principal::User.new(Identity::Principal::User.new(id: SecureRandom.uuid, email: "op@ceiba.test", full_name: "Operador"))
    Current.set(principal: operator) { Access::GrantRole.call(user:, role_key: "org_admin", organization:) }
    Access::GrantRole.call(user:, role_key: "company_manager", organization:, company: world.company_a)

    expect(events.map { |event| [ event.actor_type, event.actor_id ] }).to eq([ [ "user", operator.id ], [ "system", nil ] ])
  end

  it "un rollback posterior del llamador no deja ni membership ni evento (misma transacción)" do
    ApplicationRecord.transaction(requires_new: true) do
      Access::GrantRole.call(user:, role_key: "org_admin", organization:)
      raise ActiveRecord::Rollback
    end

    expect([ events, with_tenant(organization) { Access::Membership.where(user_id: user.id).count } ]).to eq([ [], 0 ])
  end

  it "si la auditoría falla, la concesión se revierte (no hay membership sin rastro)" do
    allow(Audit).to receive(:record).and_raise(ActiveRecord::StatementInvalid, "boom")

    expect { Access::GrantRole.call(user:, role_key: "org_admin", organization:) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(with_tenant(organization) { Access::Membership.where(user_id: user.id).count }).to eq(0)
  end

  describe "el hook del dueño de la provisión (OwnerHook)" do
    it "audita membership.granted del org_owner, junto con organization.provisioned" do
      result = Tenancy::ProvisionOrganization.call(
        organization: { name: "Grupo Auditado" }, company: { name: "Salón", slug: "salon-owner-audit", business_type: "salon", currency: "NIO" },
        branch: { name: "Central" }, extras: { owner: user }
      )

      actions = with_tenant(result.organization) { Audit::Event.order(:id).pluck(:action) }
      expect(actions).to include("organization.provisioned", "membership.granted")
    end
  end
end
