module Imports
  # The user who confirmed a batch, as the principal of the job that applies it: the audit trail of every row (and of
  # the batch) names that person instead of "system". It carries no permissions; authorization happened at confirmation.
  Actor = Data.define(:id) do
    def actor_type = "user"
  end
end
