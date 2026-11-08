require "rails_helper"

# Política de M0.02: bundler-audit puede ignorar un aviso solo con motivo y fecha de revisión,
# y la fecha no puede estar vencida. Nunca un ignore permanente.
RSpec.describe "Lista de ignorados de bundler-audit" do
  let(:path) { Rails.root.join(".bundler-audit.yml") }
  let(:config) { YAML.safe_load_file(path, permitted_classes: [ Date ]) }
  let(:entries) { path.each_line.grep(/^\s*-\s+\S/) }

  it "existe y es YAML válido con la clave ignore" do
    expect(config).to include("ignore")
  end

  it "cada ignorado declara motivo y fecha de revisión (revisar: AAAA-MM-DD | motivo: ...)" do
    expect(entries).to all(match(/#\s*revisar:\s*\d{4}-\d{2}-\d{2}\s*\|\s*motivo:\s*\S+/))
  end

  it "ningún ignorado tiene la fecha de revisión vencida" do
    dates = entries.filter_map { |line| line[/revisar:\s*(\d{4}-\d{2}-\d{2})/, 1] }.map { |date| Date.iso8601(date) }

    expect(dates).to all(be >= Date.current)
  end
end
