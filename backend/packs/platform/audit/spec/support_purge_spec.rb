require "rails_helper"

# Specs with a real COMMIT that audit must be able to clean up: purge_organizations (spec/support/tenancy_helpers.rb)
# deletes, as the OWNER and with the trigger disabled only inside its transaction, the audit_events rows of the
# organizations and the auth_audit_events rows of the given users. Without this an audited organization could not be
# deleted (FK RESTRICT).
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
