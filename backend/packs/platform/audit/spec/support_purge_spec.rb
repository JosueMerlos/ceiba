require "rails_helper"

# Los specs con COMMIT real que auditan deben poder limpiar: purge_organizations (spec/support/tenancy_helpers.rb) borra, con
# el DUEÑO y el trigger desactivado solo dentro de su transacción, las filas de audit_events de las organizaciones y las de
# auth_audit_events de los usuarios indicados. Sin esto una organización auditada no se podría borrar (FK RESTRICT).
RSpec.describe "Limpieza de specs con tablas append-only" do
  self.use_transactional_tests = false

  let!(:organization) { create(:organization) }
  let(:user_id) { SecureRandom.uuid }

  after { purge_organizations([ organization ], user_ids: [ user_id ]) }

  it "borra audit_events de la organización y auth_audit_events de los usuarios, y luego la organización" do
    with_tenant(organization) { Audit.record(action: "x.created", subject: organization) }
    Audit.record_auth(action: "auth.login_failed", user_id:)

    purge_organizations([ organization ], user_ids: [ user_id ])

    expect(Tenancy::Organization.where(id: organization.id)).to be_empty
    expect(Audit::AuthEvent.where(user_id:)).to be_empty
  end

  it "el trigger sigue activo después de limpiar" do
    purge_organizations([ organization ], user_ids: [ user_id ])
    Audit.record_auth(action: "auth.login_failed", user_id:)

    expect { ApplicationRecord.connection.execute("DELETE FROM auth_audit_events") }.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
  end
end
