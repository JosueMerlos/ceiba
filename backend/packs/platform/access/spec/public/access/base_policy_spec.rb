require "rails_helper"

# DENY BY DEFAULT: a policy that says nothing denies everything; a listing without a Scope returns no rows.
RSpec.describe Access::BasePolicy do
  let(:principal) { Access::Principal::System.new } # the most powerful principal: the base still denies
  let(:policy) { described_class.new(principal, Object.new) }

  it "niega todas las acciones estándar" do
    actions = %i[index? show? create? new? update? edit? destroy?]

    expect(actions.map { |action| policy.public_send(action) }).to all(be(false))
  end

  it "su Scope no devuelve nada por defecto" do
    relation = Tenancy::Directory.organizations_for([])

    expect(described_class::Scope.new(principal, relation).resolve).to be_empty
  end

  it "can? pregunta al principal y un permiso sin registrar es un error, no una denegación" do
    subclass = Class.new(described_class) do
      def probe(key) = can?(key, Access::Scope.organization("0198f0a0-0000-7000-8000-000000000000"))
    end

    expect(subclass.new(principal, nil).probe("platform.branch.read")).to be(true)
    expect { subclass.new(principal, nil).probe("platform.no.registrado") }.to raise_error(Access::UnknownPermission)
  end
end
