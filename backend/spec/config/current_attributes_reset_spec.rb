require "rails_helper"

# A spec that leaves global state (Current, Observability::LogContext, acts_as_tenant's tenant) must not infect the one
# that runs next: with `--seed 5718` log_fields_spec saw an organization_id left by another spec (it fails on main too).
# The global reset lives in spec/support/current_attributes_reset.rb; these two examples run IN ORDER (defined): the
# first dirties, the second requires everything clean.
RSpec.describe "reinicio global del estado de specs", order: :defined do
  it "(1) deja estado sucio a propósito" do
    Observability::LogContext.organization_id = "org-sucia"
    Current.principal = Object.new
    ActsAsTenant.current_tenant = Tenancy::Organization.new(id: SecureRandom.uuid)

    expect(Observability::LogContext.organization_id).to eq("org-sucia")
  end

  it "(2) empieza sin Current, sin LogContext y sin tenant de acts_as_tenant" do
    expect(Observability::LogContext.organization_id).to be_nil
    expect(Current.principal).to be_nil
    expect(ActsAsTenant.current_tenant).to be_nil
  end
end
