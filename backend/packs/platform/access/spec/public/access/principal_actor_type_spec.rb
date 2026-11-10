require "rails_helper"

# Every principal exposes `actor_type` and `id`; Audit and Idempotency use them as is and do NOT derive them from the class name.
RSpec.describe "Access::Principal: actor_type e id" do
  let(:identity) { Identity::Principal::User.new(id: SecureRandom.uuid, email: "ana@ceiba.test", full_name: "Ana") }

  it "User es `user` y su id es el del usuario" do
    principal = Access::Principal::User.new(identity)

    expect([ principal.actor_type, principal.id ]).to eq([ "user", identity.id ])
  end

  it "System, ApiKey y PublicToken declaran su tipo y no tienen id todavía" do
    principals = [ Access::Principal::System.new, Access::Principal::ApiKey.new, Access::Principal::PublicToken.new ]

    expect(principals.map { |principal| [ principal.actor_type, principal.id ] }).to eq([ [ "system", nil ], [ "api_key", nil ], [ "public_token", nil ] ])
  end

  it "el tipo coincide con `kind` (una sola fuente de verdad)" do
    principals = [ Access::Principal::User.new(identity), Access::Principal::System.new, Access::Principal::ApiKey.new, Access::Principal::PublicToken.new ]

    expect(principals.map(&:actor_type)).to eq(principals.map { |principal| principal.kind.to_s })
  end

  it "un principal sin actor_type es un error del llamador (no se adivina por el nombre de su clase)" do
    stranger = Struct.new(:id).new(SecureRandom.uuid)

    expect { Audit::Actor.resolve(stranger) }.to raise_error(ArgumentError, /actor_type/)
    expect { Idempotency::Actor.type_of(stranger) }.to raise_error(ArgumentError, /actor_type/)
  end

  it "Identity::Principal::User (el principal antes de envolverlo en Access) también declara `user`" do
    expect(identity.actor_type).to eq("user")
  end
end
