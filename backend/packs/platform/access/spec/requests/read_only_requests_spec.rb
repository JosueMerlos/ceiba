require "rails_helper"

# GET requests run in a READ-ONLY transaction (Access::RouteContextResolver). No transactional fixtures: the real BEGIN is
# what is observed.
RSpec.describe "Transacciones de solo lectura en GET", type: :request do
  self.use_transactional_tests = false

  let!(:world) { build_access_world }
  let!(:user) { user_with_role("org_admin", world) }

  after do
    purge_organizations([ world.organization ], user_ids: [ user.id ])
    ApplicationRecord.connection.execute("DELETE FROM sessions WHERE user_id = #{ApplicationRecord.connection.quote(user.id)}")
    Identity::User.where(id: user.id).delete_all
  end

  def statements
    captured = []
    callback = ->(*, payload) { captured << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    captured
  end

  it "un GET con contexto pide SET TRANSACTION READ ONLY antes de leer" do
    sign_in(user, password: AuthenticationHelpers::DEFAULT_PASSWORD)

    sql = statements { get "/api/v1/organizations/#{world.organization.id}/companies" }

    expect(response).to have_http_status(:ok)
    expect(sql).to include(a_string_matching(/\ASET TRANSACTION READ ONLY/))
  end

  it "una escritura en un GET fallaría en la base (la transacción es de solo lectura)" do
    sign_in(user, password: AuthenticationHelpers::DEFAULT_PASSWORD)
    allow(Tenancy::Directory).to receive(:companies).and_wrap_original do |original|
      ApplicationRecord.connection.execute("UPDATE companies SET name = name")
      original.call
    end
    allow(Api::ErrorReporter).to receive(:call)

    get "/api/v1/organizations/#{world.organization.id}/companies"

    expect(response).to have_http_status(:internal_server_error)
    expect(Api::ErrorReporter).to have_received(:call).with(instance_of(ActiveRecord::StatementInvalid), any_args)
  end
end
