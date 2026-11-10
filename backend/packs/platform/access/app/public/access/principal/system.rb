module Access
  module Principal
    # Internal jobs (relay, purges, scheduled tasks) act as the system: trusted, bypassing memberships.
    # No HTTP request builds it. Even so, an unregistered permission is still an error.
    class System
      include Principal

      def kind = :system

      def can?(permission_key, _scope)
        Principal.ensure_registered!(permission_key)
        true
      end
    end
  end
end
