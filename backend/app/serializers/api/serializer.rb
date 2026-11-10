module Api
  # Base for API serializers: `class Tenancy::OrganizationSerializer < Api::Serializer`. One serializer per
  # representation (summary, detail...), never one with conditionals. Unlisted fields do NOT go out: adding a field is a
  # decision visible in the diff AND in the contract (rswag validates with a strict schema and CI regenerates
  # openapi/v1.yaml).
  class Serializer
    include Alba::Resource
  end
end
