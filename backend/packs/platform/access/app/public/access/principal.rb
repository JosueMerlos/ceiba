module Access
  # Who is acting. Authorization asks the PRINCIPAL, not the user: all of them answer `can?(permission_key, scope)` and
  # differ by `kind`.
  #
  #   User         panel (session cookie): permissions from memberships
  #   System       internal jobs
  #   ApiKey       integrations (Bearer): interface only for now
  #   PublicToken  end customer with a signed link: interface only for now
  module Principal
    def can?(_permission_key, _scope) = raise(NotImplementedError, "#{self.class} debe implementar can?(permission_key, scope)")
    def kind = raise(NotImplementedError, "#{self.class} debe implementar kind")

    # Contract with audit and idempotency: `actor_type` ("user", "system", "api_key", "public_token") and `id` (the actor's
    # uuid; nil if the principal has no identity of its own, like system jobs). Audit and Idempotency use them as is and
    # do not derive the type from the class name.
    def actor_type = kind.to_s
    def id = nil

    # An unregistered permission is a bug in the asking code, not a denial.
    def self.ensure_registered!(permission_key)
      raise UnknownPermission, permission_key unless Access.registered?(permission_key)
    end
  end
end
