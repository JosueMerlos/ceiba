module Tenancy
  # Organization summary for the CONTEXT SELECTOR (GET /organizations): only what is needed to choose (id, name, status).
  # Legal name, country and dates come with the detail, which requires permission. Matches components.schemas.OrganizationSummary.
  class OrganizationSummarySerializer < Api::Serializer
    attributes :id, :name, :status
  end
end
