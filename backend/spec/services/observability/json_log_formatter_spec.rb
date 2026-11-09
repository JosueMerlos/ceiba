require "rails_helper"

RSpec.describe Observability::JsonLogFormatter do
  subject(:formatter) { described_class.new }

  let(:time) { Time.utc(2026, 11, 9, 12, 30, 15, 123_000) }

  def line(message, severity: "INFO") = JSON.parse(formatter.call(severity, time, nil, message))

  it "emite UNA línea JSON terminada en salto de línea" do
    output = formatter.call("INFO", time, nil, "hola")

    expect(output).to end_with("\n")
    expect(output.chomp).not_to include("\n")
  end

  it "un texto sale como msg, con ts en ISO 8601 (UTC, milisegundos) y level" do
    expect(line("hola")).to eq("ts" => "2026-11-09T12:30:15.123Z", "level" => "INFO", "msg" => "hola")
  end

  it "un Hash (la línea de lograge) se aplana en la raíz" do
    expect(line({ method: "GET", status: 200 }, severity: "WARN")).to include("level" => "WARN", "method" => "GET", "status" => 200)
  end

  it "una excepción sale con su clase y mensaje" do
    expect(line(RuntimeError.new("boom"))["msg"]).to eq("RuntimeError: boom")
  end

  it "conserva las etiquetas (tagged) como lista" do
    formatter.tagged("job") { expect(line("hola")["tags"]).to eq([ "job" ]) }
  end

  it "una línea multilínea sigue siendo UNA línea JSON (el salto va escapado)" do
    expect(formatter.call("ERROR", time, nil, "a\nb").lines.size).to eq(1)
  end
end
