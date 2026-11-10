require "rails_helper"

# The development log must carry no SQL query values (emails, phones...) nor color codes.
RSpec.describe "Configuración del log" do
  it "sin códigos de color ANSI: rompen el JSON de cada línea" do
    expect(ActiveSupport::LogSubscriber.colorize_logging).to be(false)
  end

  it "en desarrollo el nivel por defecto es info: el SQL (debug) lleva literales con datos personales y no se escribe" do
    output = IO.popen({ "RAILS_ENV" => "development", "RAILS_LOG_LEVEL" => nil }, [ "bin/rails", "runner", "puts Rails.logger.level", { err: File::NULL } ], &:read)

    expect(output.lines.last.to_i).to eq(Logger::INFO)
  end

  it "RAILS_LOG_LEVEL=debug lo activa a conciencia (depurar SQL en local)" do
    output = IO.popen({ "RAILS_ENV" => "development", "RAILS_LOG_LEVEL" => "debug" }, [ "bin/rails", "runner", "puts Rails.logger.level", { err: File::NULL } ], &:read)

    expect(output.lines.last.to_i).to eq(Logger::DEBUG)
  end
end
