module Identity
  # Public representation of the authenticated person (Identity::Principal::User). Must match components.schemas.User
  # EXACTLY.
  class UserSerializer < Api::Serializer
    attributes :id, :email, :full_name
  end
end
