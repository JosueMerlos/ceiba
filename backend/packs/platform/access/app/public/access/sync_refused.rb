module Access
  # Access.sync! refused to touch the database: the registry is empty or it would remove permissions/grants without
  # authorization. Nothing was changed.
  class SyncRefused < Error; end
end
