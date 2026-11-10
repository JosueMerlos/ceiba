require "rails_helper"
require "rubocop"
require "rubocop/rspec/support"
require "rubocop/cop/ceiba/module_gate_skips"

# The 404 of an inactive module is emitted by ensure_required_module_enabled! (Modules::RequiresModule). Skipping it in
# a controller with `requires_module` leaves the module's routes open with the module off.
RSpec.describe RuboCop::Cop::Ceiba::ModuleGateSkips, :config do
  let(:ruby_version) { 3.4 }
  let(:cop_config) { { "Include" => [ "packs/*/*/app/controllers/**/*.rb" ] } }
  let(:path) { "packs/modules/appointments/app/controllers/api/v1/appointments/bookings_controller.rb" }

  def flagged(body) = inspect_source("class BookingsController < Api::BaseController\n#{body}\nend\n", path).map { |offense| offense.location.source }

  it "acepta un controlador que declara el módulo" do
    expect(flagged("  include Modules::RequiresModule\n  requires_module :appointments")).to be_empty
  end

  it "rechaza skip_before_action del gate, con o sin only/except" do
    expect(flagged("  skip_before_action :ensure_required_module_enabled!\n  skip_before_action :ensure_required_module_enabled!, only: :show")).to eq(
      [ "skip_before_action :ensure_required_module_enabled!", "skip_before_action :ensure_required_module_enabled!, only: :show" ]
    )
  end

  it "rechaza skip_callback, redefinirlo o desactivarlo" do
    source = "  skip_callback :process_action, :before, :ensure_required_module_enabled!\n  def ensure_required_module_enabled! = true\n  undef_method :ensure_required_module_enabled!"
    expect(flagged(source).size).to eq(3)
  end

  it "rechaza el nombre del gate escrito como cadena (define_method, alias_method, undef_method, send)" do
    source = "  define_method(\"ensure_required_module_enabled!\") { true }\n  alias_method \"ensure_required_module_enabled!\", :otro\n  " \
             "undef_method \"ensure_required_module_enabled!\"\n  skip_before_action \"ensure_required_module_enabled!\""
    expect(flagged(source).size).to eq(4)
  end

  it "rechaza required_module = nil escrito a mano" do
    expect(flagged("  self.required_module = nil")).to eq([ "self.required_module = nil" ])
  end

  it "ignora otros skip_before_action" do
    expect(flagged("  skip_before_action :algo")).to be_empty
  end
end
