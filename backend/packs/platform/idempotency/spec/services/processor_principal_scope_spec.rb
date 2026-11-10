require "rails_helper"

# Key scope per principal: `actor_type:id`; a principal WITHOUT an id (ApiKey and PublicToken for now, System) shares
# the `anonymous` scope and so requires a UUID key.
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
