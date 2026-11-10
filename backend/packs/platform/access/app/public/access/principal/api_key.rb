module Access
  module Principal
    # API key (Bearer) integrations. INTERFACE ONLY: scopes `read:<module>` / `write:<module>` are not yet translated to
    # permissions. It denies everything, so nothing can build one that authorizes by mistake.
    class ApiKey
      include Principal

      def kind = :api_key

      def can?(permission_key, _scope)
        Principal.ensure_registered!(permission_key)
        false
      end
    end
  end
end
