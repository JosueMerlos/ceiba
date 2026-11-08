ENV["RAILS_ENV"] ||= "test"
require "spec_helper"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

# Helpers compartidos (spec/support/**/*.rb).
Rails.root.glob("spec/support/**/*.rb").sort.each { |file| require file }

# Esquema de test al día (db:prepare como dueño en un subproceso si hace falta): ver spec/support/test_schema.rb.
TestSchema.ensure_current!

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
end
