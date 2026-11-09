require "rails_helper"

# Alcance de la clave por principal (M0.11 con los principales de M0.08): `actor_type:id`; un principal SIN id (ApiKey y
# PublicToken hasta M4.02/M3.04, System) comparte el alcance `anonymous` y por eso exige una clave UUID.
RSpec.describe Idempotency::Processor do # rubocop:disable RSpec/SpecFilePathFormat
  def scope_for(principal) = Current.set(principal:) { described_class.new(request: nil, response: nil, required: false).send(:principal_key) }

  it "un usuario de acceso: user:<id>" do
    principal = Access::Principal::User.new(Identity::Principal::User.new(id: "0198f0a0-0000-7000-8000-00000000abcd", email: "a@b.test", full_name: "A"))

    expect(scope_for(principal)).to eq("user:0198f0a0-0000-7000-8000-00000000abcd")
  end

  it "sin principal, o con uno sin id: anonymous" do
    expect([ scope_for(nil), scope_for(Access::Principal::PublicToken.new), scope_for(Access::Principal::ApiKey.new) ]).to all(eq("anonymous"))
  end
end
