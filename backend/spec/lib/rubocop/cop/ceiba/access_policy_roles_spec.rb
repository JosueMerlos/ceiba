require "rails_helper"
require "rubocop"
require "rubocop/rspec/support"
require "rubocop/cop/ceiba/access_policy_roles"

# Criterio 7 de M0.08: una policy que compara un nombre de rol (o pregunta `admin?`) FALLA el linter (ADR-0008: las policies
# preguntan por permisos, nunca por roles).
RSpec.describe RuboCop::Cop::Ceiba::AccessPolicyRoles, :config do
  include RuboCop::RSpec::ExpectOffense

  let(:cop_config) { { "Include" => [ "packs/*/*/app/policies/**/*.rb" ] } }
  let(:policy_path) { "packs/modules/appointments/app/policies/appointments/appointment_policy.rb" }

  it "acepta una policy que pregunta por permisos" do
    expect_no_offenses(<<~RUBY, policy_path)
      class Appointments::AppointmentPolicy < Access::BasePolicy
        def create? = can?("appointments.appointment.create", record.branch)
      end
    RUBY
  end

  it "rechaza comparar un nombre de rol como cadena" do
    expect_offense(<<~RUBY, policy_path)
      class Appointments::AppointmentPolicy < Access::BasePolicy
        def create? = principal.role == "receptionist"
                                  ^^^^ Las policies preguntan por permisos (`can?`), no por roles: [...]
                                          ^^^^^^^^^^^^^^ Las policies preguntan por permisos (`can?`), no por roles: [...]
      end
    RUBY
  end

  it "rechaza un nombre de rol como símbolo o dentro de un arreglo" do
    expect_offense(<<~RUBY, policy_path)
      class Appointments::AppointmentPolicy < Access::BasePolicy
        def update? = %i[org_owner org_admin].include?(x)
                       ^^^^^^^^^^^^^^^^^^^^^^ Las policies preguntan por permisos (`can?`), no por roles: [...]
      end
    RUBY
  end

  it "rechaza admin? y las consultas de rol" do
    expect_offense(<<~RUBY, policy_path)
      class Appointments::AppointmentPolicy < Access::BasePolicy
        def destroy? = user.admin? || user.has_role?(:x) || user.roles.any?
                            ^^^^^^ Las policies preguntan por permisos (`can?`), no por roles: [...]
                                       ^^^^^^^^^ Las policies preguntan por permisos (`can?`), no por roles: [...]
                                                              ^^^^^ Las policies preguntan por permisos (`can?`), no por roles: [...]
      end
    RUBY
  end

  it "no revisa archivos que no son policies" do
    expect_no_offenses(<<~RUBY, "packs/platform/access/app/services/access/catalog_sync.rb")
      SYSTEM = %w[org_owner receptionist]
    RUBY
  end
end
