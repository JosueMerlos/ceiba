module Identity
  # Respuesta de login y de GET /auth/session. EXACTAMENTE components.schemas.AuthSession.
  class AuthSessionSerializer < Api::Serializer
    one :principal, key: :user, resource: UserSerializer
    attributes :csrf_token, expires_at: :iso8601
  end
end
