require "rails_helper"
require "ci/audit_ignore_policy"

# No bundler-audit ignore without a reason and a current review date. The logic lives in lib/ci (tested in spec/lib) so
# this spec cannot pass trivially with an empty list.
RSpec.describe "Lista de ignorados de bundler-audit" do
  it "cumple la política (motivo, fecha de revisión y sin vencer)" do
    policy = AuditIgnorePolicy.new(Rails.root.join(".bundler-audit.yml").read, today: Date.current)

    expect(policy.violations).to be_empty
  end
end
