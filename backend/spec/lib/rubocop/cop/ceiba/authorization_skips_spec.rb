require "rails_helper"
require "rubocop"
require "rubocop/rspec/support"
require "rubocop/cop/ceiba/authorization_skips"

# La ÚNICA forma de no autorizar una acción es skip_authorization!(reason:, only:) (queda en la allowlist del spec de rutas).
# Saltarse las verificaciones por otro camino abre un agujero sin rastro.
RSpec.describe RuboCop::Cop::Ceiba::AuthorizationSkips, :config do
  let(:ruby_version) { 3.4 }
  let(:cop_config) { { "Include" => [ "packs/*/*/app/controllers/**/*.rb" ] } }
  let(:path) { "packs/modules/appointments/app/controllers/api/v1/appointments/bookings_controller.rb" }

  def flagged(body) = inspect_source("class BookingsController < Api::BaseController\n#{body}\nend\n", path).map { |offense| offense.location.source }

  it "acepta skip_authorization! con motivo" do
    expect(flagged('  skip_authorization! reason: "es una sonda", only: :show')).to be_empty
  end

  it "rechaza skip_after_action de las verificaciones de Pundit" do
    expect(flagged("  skip_after_action :verify_authorized\n  skip_after_action :verify_policy_scoped, only: :index")).to eq(
      [ "skip_after_action :verify_authorized", "skip_after_action :verify_policy_scoped, only: :index" ]
    )
  end

  it "rechaza skip_authorization y skip_policy_scope dentro de una acción" do
    expect(flagged("  def show\n    skip_authorization\n    skip_policy_scope\n  end")).to eq([ "skip_authorization", "skip_policy_scope" ])
  end

  it "rechaza saltarse las verificaciones con skip_callback o redefiniéndolas" do
    expect(flagged("  skip_callback :process_action, :after, :verify_authorized\n  def verify_authorized = true")).to eq(
      [ "skip_callback :process_action, :after, :verify_authorized", "verify_authorized" ]
    )
  end

  it "rechaza asignar @_pundit_* y redefinir las verificaciones con define_method o alias" do
    expect(flagged("  def show\n    @_pundit_policy_authorized = true\n    @_pundit_policy_scoped = true\n  end\n  define_method(:verify_authorized) { }\n  alias_method :verify_collection_scoped, :foo\n  undef_method :verify_policy_scoped")).to eq(
      [ "@_pundit_policy_authorized = true", "@_pundit_policy_scoped = true", "define_method(:verify_authorized)",
        "alias_method :verify_collection_scoped, :foo", "undef_method :verify_policy_scoped" ]
    )
  end

  it "rechaza instance_variable_set sobre las marcas de Pundit" do
    expect(flagged("  def show = instance_variable_set(:@_pundit_policy_authorized, true)")).to eq([ "instance_variable_set(:@_pundit_policy_authorized, true)" ])
  end

  it "no toca otros skip_after_action" do
    expect(flagged("  skip_after_action :otra_cosa")).to be_empty
  end
end
