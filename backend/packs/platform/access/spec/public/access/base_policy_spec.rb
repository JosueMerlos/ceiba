require "rails_helper"

# Access::BasePolicy: DENY BY DEFAULT (ADR-0007). Una policy que no dice nada niega todo; un listado sin Scope no devuelve filas.
RSpec.describe Access::BasePolicy do
  let(:principal) { Access::Principal::System.new } # el más poderoso: aun así la base niega
  let(:policy) { described_class.new(principal, Object.new) }

  it "niega todas las acciones estándar" do
    actions = %i[index? show? create? new? update? edit? destroy?]

    expect(actions.map { |action| policy.public_send(action) }).to all(be(false))
  end

  it "su Scope no devuelve nada por defecto" do
    relation = Tenancy::Directory.organizations

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
