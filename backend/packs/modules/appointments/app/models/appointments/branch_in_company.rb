module Appointments
  # The `branch_in_company` validation of the rows that name a branch: the branch lives in another pack, so only its id is
  # stored and the directory is what knows its company. Declare it with `validate :branch_in_company` where the order of
  # the errors matters.
  module BranchInCompany
    extend ActiveSupport::Concern

    private

    def branch_in_company
      errors.add(:branch_id, :invalid) if branch_id.blank? || Tenancy::Directory.branch_company_id(branch_id) != company_id
    end
  end
end
