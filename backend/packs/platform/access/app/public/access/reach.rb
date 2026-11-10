module Access
  # What resources of the active organization ONE permission reaches: the whole organization, or certain companies and/or
  # branches. Policy `Scope`s use it to filter listings with ONE condition instead of asking record by record:
  #
  #   reach = principal.reach("platform.branch.read")
  #   reach.organization? ? scope : scope.where(company_id: reach.company_ids).or(scope.where(id: reach.branch_ids))
  Reach = Data.define(:organization, :company_ids, :branch_ids) do
    def organization? = organization
    def none? = !organization && company_ids.empty? && branch_ids.empty?
  end
end
