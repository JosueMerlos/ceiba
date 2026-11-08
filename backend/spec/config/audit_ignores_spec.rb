require "rails_helper"
require "ci/audit_ignore_policy"

# Política de M0.02: ningún ignorado de bundler-audit sin motivo y fecha de revisión vigente.
# La lógica vive en lib/audit_ignore_policy.rb (probada en spec/lib) para que este spec no pueda
# pasar de forma trivial con la lista vacía.
RSpec.describe "Lista de ignorados de bundler-audit" do
  it "cumple la política (motivo, fecha de revisión y sin vencer)" do
    policy = AuditIgnorePolicy.new(Rails.root.join(".bundler-audit.yml").read, today: Date.current)

    expect(policy.violations).to be_empty
  end
end
