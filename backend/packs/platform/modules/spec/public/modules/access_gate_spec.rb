require "rails_helper"

# With the REAL gate (company_modules): a company_manager with `sample` permissions loses them when the module is disabled in
# their company. The gate's semantics are covered in the access pack's specs.
RSpec.describe "Permisos de un módulo y su activación en la empresa" do
  include_context "con el módulo sample sincronizado"

  let(:world) { build_access_world }
  let(:company) { world.company_a }
  let(:manager) { user_with_role("company_manager", world, company:) }
  let(:scope) { Access::Scope.company(organization_id: world.organization.id, company_id: company.id) }
  let(:permission) { "sample.thing.manage" }

  def principal = access_principal_for(manager, world.organization)
  def enable = with_tenant(world.organization) { Modules::Enable.call(company:, key: "sample") }
  def disable = with_tenant(world.organization) { Modules::Disable.call(company:, key: "sample") }
  def can?(subject = principal) = with_tenant(world.organization) { subject.can?(permission, scope) }

  it "módulo inactivo: can? es false aunque su rol tenga el permiso" do
    expect(can?).to be(false)
  end

  it "criterio 3: activo, can? es true; al desactivarlo en su empresa, false" do
    enable
    expect(can?).to be(true)

    disable
    expect(can?).to be(false)
  end

  it "reactivar devuelve el permiso" do
    enable
    disable
    enable

    expect(can?).to be(true)
  end

  it "activar el módulo en OTRA empresa no concede nada en esta" do
    with_tenant(world.organization) { Modules::Enable.call(company: world.company_b, key: "sample") }

    expect(can?).to be(false)
  end

  it "los permisos de plataforma del mismo usuario no dependen de ningún módulo" do
    expect(with_tenant(world.organization) { principal.can?("platform.branding.update", scope) }).to be(true)
  end

  it "reach: un company_manager solo llega a su empresa si el módulo está activo" do
    reach = -> { with_tenant(world.organization) { principal.reach("sample.thing.read").company_ids } }

    expect(reach.call).to be_empty
    enable
    expect(reach.call).to eq([ company.id ])
  end

  it "el principal es una foto por request: lo activado después no cambia lo ya consultado" do
    subject_principal = principal
    expect(can?(subject_principal)).to be(false)

    enable

    expect(can?(subject_principal)).to be(false)
    expect(can?).to be(true)
  end
end
