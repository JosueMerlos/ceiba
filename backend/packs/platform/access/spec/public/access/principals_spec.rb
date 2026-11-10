require "rails_helper"

# The other principals share the can?(permission, scope) interface.
RSpec.describe "Access::Principal (interfaz y principales no-usuario)" do
  let(:scope) { Access::Scope.organization("0198f0a0-0000-7000-8000-000000000000") }

  it "System (jobs internos) puede todo permiso registrado, y un permiso no registrado sigue siendo un bug" do
    expect(Access::Principal::System.new.can?("platform.branch.read", scope)).to be(true)
    expect { Access::Principal::System.new.can?("platform.nada.existe", scope) }.to raise_error(Access::UnknownPermission)
  end

  it "ApiKey y PublicToken existen como interfaz (M4.02 y M3.04) y niegan todo hasta entonces" do
    expect(Access::Principal::ApiKey.new.can?("platform.branch.read", scope)).to be(false)
    expect(Access::Principal::PublicToken.new.can?("platform.branch.read", scope)).to be(false)
  end

  it "todos responden a can? y se distinguen por #kind" do
    kinds = [ Access::Principal::System, Access::Principal::ApiKey, Access::Principal::PublicToken ].map { |klass| klass.new.kind }

    expect(kinds).to eq(%i[system api_key public_token])
  end

  it "Scope valida su forma: una sucursal exige empresa; los ids no pueden estar vacíos" do
    expect { Access::Scope.new(organization_id: "x", company_id: nil, branch_id: "b") }.to raise_error(ArgumentError)
    expect { Access::Scope.organization(nil) }.to raise_error(ArgumentError)
  end

  it "Scope sabe su nivel" do
    expect(scope.level).to eq(:organization)
    expect(Access::Scope.company(organization_id: "o", company_id: "c").level).to eq(:company)
    expect(Access::Scope.branch(organization_id: "o", company_id: "c", branch_id: "b").level).to eq(:branch)
  end
end
