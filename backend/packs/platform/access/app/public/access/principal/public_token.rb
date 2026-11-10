module Access
  module Principal
    # End customer with a signed appointment link (minimal scope). INTERFACE ONLY: denies everything for now.
    class PublicToken
      include Principal

      def kind = :public_token

      def can?(permission_key, _scope)
        Principal.ensure_registered!(permission_key)
        false
      end
    end
  end
end
