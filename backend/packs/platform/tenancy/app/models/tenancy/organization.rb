module Tenancy
  # The organization is the TENANT: the hard boundary between customers. It is the root, with no organization_id or
  # acts_as_tenant, so it can be queried without context (provisioning and the back-office do).
  class Organization < ApplicationRecord
    enum :status, { active: "active", suspended: "suspended" }, default: "active", validate: true

    # NO `has_many :companies`, on purpose: an association whose condition is `organization_id = <this organization>`
    # REPLACES the tenant scope, so from context A `Organization.find(b.id).companies` would return B's companies. Query
    # companies inside a tenant (`Tenancy.with_context(...) { Company.all }`). TenantIsolation.association_violations guards it.
    # Deleting an organization that has data is blocked by the FK (restrict), not the model.

    validates :name, presence: true
    validates :country_code, format: { with: /\A[A-Z]{2}\z/ }
  end
end
