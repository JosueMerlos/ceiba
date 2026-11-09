require "rails_helper"
require "rubocop"
require "rubocop/rspec/support"
require "rubocop/cop/ceiba/access_policy_roles"

# Criterio 7 de M0.08: una policy que compara un nombre de rol (o pregunta `admin?`) FALLA el linter (ADR-0008: las policies
# preguntan por permisos, nunca por roles).
RSpec.describe RuboCop::Cop::Ceiba::AccessPolicyRoles, :config do
  let(:ruby_version) { 3.4 }
  let(:cop_config) { { "Include" => [ "packs/*/*/app/policies/**/*.rb" ] } }
  let(:policy_path) { "packs/modules/appointments/app/policies/appointments/appointment_policy.rb" }

  def flagged(body, path = policy_path)
    source = "class Appointments::AppointmentPolicy < Access::BasePolicy\n#{body}\nend\n"
    inspect_source(source, path).map { |offense| offense.location.source }
  end

  it "acepta una policy que pregunta por permisos" do
    expect(flagged(%(  def create? = can?("appointments.appointment.create", record.branch)))).to be_empty
  end

  it "rechaza comparar un nombre de rol como cadena" do
    expect(flagged(%(  def create? = principal.role == "receptionist"))).to eq([ "role", '"receptionist"' ])
  end

  it "rechaza un nombre de rol como símbolo o dentro de %w / %i" do
    expect(flagged("  def a? = x == :org_owner\n  def b? = %w[org_admin company_manager].include?(x)")).to eq(
      [ ":org_owner", "org_admin", "company_manager" ]
    )
  end

  it "rechaza admin? y las consultas de rol" do
    expect(flagged("  def destroy? = user.admin? || user.has_role?(:x) || user.roles.any?")).to eq([ "admin?", "has_role?", "roles" ])
  end

  it "rechaza send/public_send/__send__ con una consulta de rol y instance_variable_get" do
    expect(flagged("  def a? = user.send(:admin?)\n  def b? = user.public_send(:roles)\n  def c? = user.__send__(\"has_role?\", 1)\n  def d? = user.instance_variable_get(:@role)")).to eq(
      [ ":admin?", ":roles", '"has_role?"', "instance_variable_get" ]
    )
  end

  it "rechaza claves de rol partidas: cadenas adyacentes, interpolación y concatenación" do
    expect(flagged(%q(  def a? = x == "org_" "owner"
  def b? = x == "org_#{kind}"
  def c? = x == "recep" + "tionist"))).to eq([ '"org_" "owner"', '"org_#{kind}"', '"recep" + "tionist"' ])
  end

  it "rechaza method(:role), instance_eval/instance_exec y %w[...].join con claves de rol" do
    expect(flagged("  def a? = user.method(:admin?).call\n  def b? = user.instance_eval { role }\n  def c? = user.instance_exec { 1 }\n  def d? = %w[org_ owner].join == x")).to eq(
      [ ":admin?", "instance_eval", "role", "instance_exec", "%w[org_ owner].join" ]
    )
  end

  it "el mensaje explica el porqué" do
    offense = inspect_source("class P; def a? = admin?; end", policy_path).first

    expect(offense.message).to include("permisos").and include("ADR-0008")
  end

  it "no revisa archivos que no son policies" do
    expect(flagged(%(  ROLES = %w[org_owner receptionist]), "packs/platform/access/app/services/access/catalog_sync.rb")).to be_empty
  end
end
