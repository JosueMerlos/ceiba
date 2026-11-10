require "rails_helper"
require "ci/policy_permissions"
require "tmpdir"

# A permission used in a policy and not registered makes the suite FAIL.
RSpec.describe PolicyPermissions do
  let(:root) { Pathname(Dir.mktmpdir("ceiba-policy-permissions")) }

  after { FileUtils.remove_entry(root) }

  def write_policy(path, body)
    file = root.join("packs", path)
    FileUtils.mkdir_p(file.dirname)
    File.write(file, body)
  end

  describe "#violations" do
    it "marca un permiso usado en una policy que no está registrado, con archivo y línea" do
      write_policy("modules/appointments/app/policies/appointments/appointment_policy.rb", <<~RUBY)
        class Appointments::AppointmentPolicy < Access::BasePolicy
          def create? = can?("appointments.appointment.create", record.branch)
          def cancel? = can?("appointments.appointment.cancel", record.branch)
        end
      RUBY

      violations = described_class.new(root).violations(registered: [ "appointments.appointment.create" ])

      expect(violations).to eq([ "packs/modules/appointments/app/policies/appointments/appointment_policy.rb:3: appointments.appointment.cancel" ])
    end

    it "no marca los permisos registrados ni otras cadenas con puntos" do
      write_policy("platform/x/app/policies/x/thing_policy.rb", <<~RUBY)
        class X::ThingPolicy < Access::BasePolicy
          def show? = can?("platform.thing.read", record) && record.name == "a.b" && "ok" != "1.2.3"
        end
      RUBY

      expect(described_class.new(root).violations(registered: [ "platform.thing.read" ])).to be_empty
    end

    it "no revisa archivos fuera de app/policies" do
      write_policy("platform/x/app/services/x/thing.rb", %(KEY = "no.esta.registrado"\n))

      expect(described_class.new(root).violations(registered: [])).to be_empty
    end
  end

  it "las policies reales de todos los packs solo usan permisos registrados (la suite falla si no)" do
    violations = described_class.new(Rails.root).violations(registered: Access.permission_keys)

    expect(violations).to be_empty, "permisos usados en policies y no registrados con Access.register_permissions:\n#{violations.join("\n")}"
  end

  it "las policies reales usan al menos un permiso (el escáner de verdad lee los archivos)" do
    expect(described_class.new(Rails.root).used_permissions).to include("platform.branch.read")
  end
end
