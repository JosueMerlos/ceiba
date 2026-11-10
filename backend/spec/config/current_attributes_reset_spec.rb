require "rails_helper"

# Un spec que deja estado global (Current, Observability::LogContext, el tenant de acts_as_tenant) no debe contagiar al que
# corre después: con `--seed 5718` log_fields_spec veía un organization_id dejado por otro spec (falla también en main).
# El reinicio global vive en spec/support/current_attributes_reset.rb; estos dos ejemplos corren EN ORDEN (definido): el
# primero ensucia, el segundo exige que todo esté limpio.
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
