# Access errors the API translates to problem+json (see Api::ErrorRegistry).
#
# - Pundit::NotAuthorizedError: the resource is visible but the action is not allowed => 403. Anything not visible NEVER
#   gets here: Access::RouteContextResolver answers 404 (RecordNotFound) so existence is not revealed.
# - Access::OrganizationSuspended => 403 (the principal is a member; otherwise it would have received 404).
# - AuthorizationNotPerformedError / PolicyScopingNotPerformedError and Access::UnknownPermission are deliberately NOT
#   registered: they are code bugs (an action without authorize, an undeclared permission) and surface as a generic 500
#   with the details in the log.
Rails.application.config.to_prepare do
  Api::ErrorRegistry.register(Pundit::NotAuthorizedError, status: :forbidden, code: "access.forbidden")
  Api::ErrorRegistry.register(Access::OrganizationSuspended, status: :forbidden, code: "access.organization_suspended")
end
