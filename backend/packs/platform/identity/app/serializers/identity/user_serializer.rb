module Identity
  # Representación pública de la persona autenticada (Identity::Principal::User). EXACTAMENTE components.schemas.User.
  class UserSerializer < Api::Serializer
    attributes :id, :email, :full_name
  end
end
