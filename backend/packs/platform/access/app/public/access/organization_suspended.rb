module Access
  # The route's organization is suspended: its members cannot operate under it (403 access.organization_suspended).
  # Non-members never reach this error: they get 404 first, so suspension does not reveal the organization exists.
  class OrganizationSuspended < Error; end
end
