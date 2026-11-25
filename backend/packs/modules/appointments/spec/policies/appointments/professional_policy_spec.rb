require "rails_helper"

# The professional's contact is personal data: only who manages the company's professionals reads it.
RSpec.describe Appointments::ProfessionalPolicy do
  let(:world) { build_access_world }
  let(:professional) { create_in(world.organization, :professional, company: world.company_a) }

  before { with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "appointments") } }

  def member_of(role)
    case role
    when "company_manager" then user_with_role(role, world, company: world.company_a)
    when "branch_manager", "receptionist", "professional" then user_with_role(role, world, branch: world.branch_a1)
    else user_with_role(role, world)
    end
  end

  def contact_for(role)
    policy = described_class.new(access_principal_for(member_of(role), world.organization), professional)
    Tenancy.with_context(organization: world.organization, company: world.company_a) { policy.contact? }
  end

  describe "#contact?" do
    it "solo el company_manager lee el contacto; ningún otro rol, tampoco los de organización" do
      roles = %w[org_owner org_admin company_manager branch_manager receptionist professional]

      expect(roles.to_h { [ it, contact_for(it) ] }).to eq(
        "org_owner" => false, "org_admin" => false, "company_manager" => true,
        "branch_manager" => false, "receptionist" => false, "professional" => false
      )
    end
  end
end
