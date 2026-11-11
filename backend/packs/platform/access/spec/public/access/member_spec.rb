require "rails_helper"

# Access.member? answers whether a person holds ANY membership in an organization, so a module can refuse to link a user
# who has nothing to do with it. It reads inside the active tenant and never crosses organizations.
RSpec.describe "Access.member?" do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:user) { create(:user) }

  it "es verdadero para quien tiene una membresía en la organización" do
    user_with_role("receptionist", organization, branch: create_in(organization, :branch), user:)

    with_tenant(organization) { expect(Access.member?(user_id: user.id, organization_id: organization.id)).to be(true) }
  end

  it "es falso para un usuario sin ninguna membresía" do
    with_tenant(organization) { expect(Access.member?(user_id: user.id, organization_id: organization.id)).to be(false) }
  end

  it "es falso para quien solo es miembro de OTRA organización (no cruza organizaciones)" do
    user_with_role("org_admin", other_organization, user:)

    with_tenant(organization) { expect(Access.member?(user_id: user.id, organization_id: organization.id)).to be(false) }
  end

  it "es falso si se pregunta por una organización distinta de la activa, aunque el usuario sea miembro de ella" do
    user_with_role("org_admin", other_organization, user:)

    with_tenant(organization) { expect(Access.member?(user_id: user.id, organization_id: other_organization.id)).to be(false) }
  end
end
