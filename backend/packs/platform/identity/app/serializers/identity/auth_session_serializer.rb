module Identity
  # Login and GET /auth/session response. Must match components.schemas.AuthSession EXACTLY.
  class AuthSessionSerializer < Api::Serializer
    one :principal, key: :user, resource: UserSerializer
    attributes :csrf_token, expires_at: :iso8601
  end
end
