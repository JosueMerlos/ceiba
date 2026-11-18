module Access
  # Creates a branch of the route's company and audits `branch.created` in the same savepoint: no event, no branch.
  # Access (not Tenancy) records it because tenancy does not know audit. Only non-personal attributes are recorded.
  module CreateBranch
    AUDITED_FIELDS = %w[company_id name time_zone status].freeze

    module_function

    def call(company:, attributes:)
      ApplicationRecord.transaction(requires_new: true) do
        branch = ::Tenancy::AddBranch.call(company:, **attributes)
        Audit.record(action: "branch.created", subject: branch, after: branch.attributes.slice(*AUDITED_FIELDS))
        branch
      end
    end
  end
end
