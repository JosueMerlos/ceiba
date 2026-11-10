module Identity
  # Creates a user from code (seeds, console). Idempotent by email: an existing user is returned as is, WITHOUT touching
  # their password or name (a repeated seed must not overwrite what the user changed).
  #
  # Not the public sign-up nor an invitation; no endpoint exposes it.
  #
  #   Identity::ProvisionUser.call(email: "ana@ceiba.test", full_name: "Ana Pérez", password: "…12 or more characters…")
  #   # => Identity::Principal::User
  module ProvisionUser
    def self.call(email:, full_name:, password:)
      user = User.find_by(email:) || create(email:, full_name:, password:)
      Principal::User.new(id: user.id, email: user.email, full_name: user.full_name)
    end

    # Two simultaneous seeds: the unique index wins and the loser reads the winner's row.
    def self.create(email:, full_name:, password:)
      User.create!(email:, full_name:, password:)
    rescue ActiveRecord::RecordNotUnique
      User.find_by!(email:)
    end
    private_class_method :create
  end
end
