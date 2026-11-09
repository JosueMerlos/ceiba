require "rails_helper"

# M0.09: el permiso efectivo exige además que el MÓDULO del permiso esté activo en la empresa del recurso (docs/architecture/04 y
# 05). access no conoce a platform/modules (ciclo): este es el punto de extensión `Access.module_gate`, que modules implementa.
# Aquí se prueba el contrato con un gate de mentira; la integración real (company_modules) está en el spec de modules.
RSpec.describe "Access.module_gate (permisos de un módulo inactivo no aplican)" do
  include_context "con el módulo sample sincronizado"

  # Un gate de mentira: qué módulos controla y en qué empresas están activos. Cuenta cuántas veces se le pregunta.
  let(:gate_class) do
    Class.new do
      attr_reader :loads

      def initialize(active) = (@active = active) && (@loads = 0)
      def gated?(module_key) = module_key.start_with?("sample")

      def active_companies_by_module
        @loads += 1
        @active
      end
    end
  end

  let(:organization) { create(:organization) }
  let(:company_a) { create_in(organization, :company) }
  let(:company_b) { create_in(organization, :company) }
  let(:branch_a1) { create_in(organization, :branch, company: company_a) }
  let(:branch_b1) { create_in(organization, :branch, company: company_b) }
  let(:user) { create(:user) }
  let(:read) { "sample.thing.read" }

  around do |example|
    previous = Access.module_gate
    example.run
  ensure
    Access.module_gate = previous
  end

  def gate_with(active) = (Access.module_gate = gate_class.new(active))

  def role_with(permission_key, scope_level)
    create(:role, scope_level:).tap { |role| Access::RolePermission.create!(role:, permission_key:) }
  end

  def grant(role, company: nil, branch: nil)
    with_tenant(organization) { create(:membership, user_id: user.id, role:, company_id: company&.id, branch_id: branch&.id) }
  end

  def principal
    [ branch_a1, branch_b1 ]
    Access::Principal::User.new(Identity::Principal::User.new(id: user.id, email: user.email, full_name: user.full_name)).tap do |principal|
      with_tenant(organization) { principal.activate!(organization.id) }
    end
  end

  def company_scope(company) = Access::Scope.company(organization_id: organization.id, company_id: company.id)
  def branch_scope(branch) = Access::Scope.branch(organization_id: organization.id, company_id: branch.company_id, branch_id: branch.id)

  context "sin gate configurado" do
    it "el permiso de un módulo se concede por membership como siempre" do
      Access.module_gate = nil
      grant(role_with(read, "company"), company: company_a)

      expect(principal.can?(read, company_scope(company_a))).to be(true)
    end
  end

  context "con el módulo activo en una empresa y no en otra" do
    before do
      gate_with("sample" => Set[company_a.id])
      grant(role_with(read, "organization"))
    end

    it "concede en la empresa y la sucursal donde está activo" do
      expect(principal.can?(read, company_scope(company_a))).to be(true)
      expect(principal.can?(read, branch_scope(branch_a1))).to be(true)
    end

    it "niega en la empresa y la sucursal donde está inactivo, aunque el membership de organización lo cubra" do
      expect(principal.can?(read, company_scope(company_b))).to be(false)
      expect(principal.can?(read, branch_scope(branch_b1))).to be(false)
    end

    it "a nivel de organización concede si el módulo está activo en alguna empresa" do
      expect(principal.can?(read, Access::Scope.organization(organization.id))).to be(true)
    end

    it "a nivel de organización niega si no está activo en ninguna" do
      gate_with({})

      expect(principal.can?(read, Access::Scope.organization(organization.id))).to be(false)
    end
  end

  it "los permisos de plataforma no dependen de ningún módulo, aunque el gate no tenga nada activo" do
    gate_with({})
    grant(role_with("platform.branch.read", "company"), company: company_a)

    expect(principal.can?("platform.branch.read", company_scope(company_a))).to be(true)
  end

  describe "una sola consulta de módulos activos por principal (memoizada, sin N+1)" do
    it "no consulta al activar ni al preguntar por un permiso de plataforma; consulta UNA vez al preguntar por uno de módulo" do
      gate = gate_with("sample" => Set[company_a.id])
      grant(role_with(read, "company"), company: company_a)
      grant(role_with("platform.branch.read", "company"), company: company_a)
      subject_principal = principal
      subject_principal.can?("platform.branch.read", company_scope(company_a))

      expect(gate.loads).to eq(0)

      30.times { subject_principal.can?(read, company_scope(company_a)) }

      expect(gate.loads).to eq(1)
    end

    it "sin contexto de tenancy no se puede saber qué módulos hay activos: se niega (y no se memoriza el fallo)" do
      gate = gate_with("sample" => Set[company_a.id])
      allow(gate).to receive(:active_companies_by_module).and_raise(ActsAsTenant::Errors::NoTenantSet)
      grant(role_with(read, "company"), company: company_a)

      expect(principal.can?(read, company_scope(company_a))).to be(false)
    end
  end

  describe "#module_active?" do
    before { gate_with("sample" => Set[company_a.id]) }

    it "responde por empresa para un módulo controlado" do
      grant(role_with(read, "organization"))
      subject_principal = principal

      expect(subject_principal.module_active?("sample", company_a.id)).to be(true)
      expect(subject_principal.module_active?("sample", company_b.id)).to be(false)
    end

    it "un módulo que el gate no controla (p. ej. platform) siempre está activo" do
      grant(role_with(read, "organization"))

      expect(principal.module_active?("platform", company_b.id)).to be(true)
    end
  end

  describe "#reach (para filtrar listados)" do
    it "un membership de organización llega a las empresas donde el módulo está activo, no a toda la organización" do
      gate_with("sample" => Set[company_a.id])
      grant(role_with(read, "organization"))

      reach = principal.reach(read)

      expect(reach).to have_attributes(organization?: false, company_ids: [ company_a.id ], branch_ids: [])
    end

    it "quita las empresas y sucursales cuyo módulo está inactivo" do
      gate_with("sample" => Set[company_a.id])
      grant(role_with(read, "company"), company: company_a)
      grant(role_with(read, "company"), company: company_b)
      grant(role_with(read, "branch"), company: company_b, branch: branch_b1)
      grant(role_with(read, "branch"), company: company_a, branch: branch_a1)

      reach = principal.reach(read)

      expect(reach).to have_attributes(company_ids: [ company_a.id ], branch_ids: [ branch_a1.id ])
    end

    it "no toca el alcance de un permiso de plataforma" do
      gate_with({})
      grant(role_with("platform.branch.read", "organization"))

      expect(principal.reach("platform.branch.read")).to be_organization
    end
  end

  describe "#permission_keys_in (lo que /me le dice al frontend)" do
    before do
      gate_with("sample" => Set[company_a.id])
      grant(role_with(read, "company"), company: company_a)
      grant(role_with("platform.branch.read", "company"), company: company_a)
      grant(role_with(read, "company"), company: company_b)
    end

    it "incluye los permisos del módulo activo en la empresa y los de plataforma" do
      expect(principal.permission_keys_in(company_id: company_a.id)).to contain_exactly(read, "platform.branch.read")
    end

    it "excluye los permisos de un módulo inactivo en la empresa del contexto" do
      expect(principal.permission_keys_in(company_id: company_b.id)).to be_empty
    end

    it "sin empresa en el contexto no hay permisos de módulo" do
      expect(principal.permission_keys_in).to be_empty
    end
  end

  describe "permission_keys_in con memberships de sucursal" do
    before do
      gate_with("sample" => Set[company_a.id])
      grant(role_with(read, "branch"), company: company_a, branch: branch_a1)
    end

    it "en el contexto de la empresa incluye lo que el usuario ejerce en alguna de sus sucursales" do
      expect(principal.permission_keys_in(company_id: company_a.id)).to include(read)
    end

    it "en el contexto de OTRA sucursal de la empresa no lo incluye" do
      other = create_in(organization, :branch, company: company_a)

      expect(principal.permission_keys_in(company_id: company_a.id, branch_id: other.id)).not_to include(read)
    end

    it "en el contexto de su sucursal sí" do
      expect(principal.permission_keys_in(company_id: company_a.id, branch_id: branch_a1.id)).to include(read)
    end
  end
end
