# Per-request/job state (ActiveSupport::CurrentAttributes).
#   context    tenancy context; ONLY Tenancy.with_context writes it: nothing else may assign it.
#   session    Identity::CurrentSession of the authenticated request; ONLY Api::Authentication#authenticate! writes it.
#   principal  who is acting (currently Identity::Principal::User).
#   request_id, ip, user_agent  of the current request (Api::RequestMetadata); the audit trail records them.
class Current < ActiveSupport::CurrentAttributes
  attribute :context, :session, :principal, :request_id, :ip, :user_agent
end
