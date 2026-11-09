require "rails_helper"
require "open3"

# `bin/rails access:sync` es lo que corre el despliegue (y db:migrate encadena): idempotente y con salida legible.
RSpec.describe "tarea access:sync" do
  def run(*args)
    Open3.capture2e({ "RAILS_ENV" => "test" }, "bin/rails", *args, chdir: Rails.root.to_s)
  end

  it "sincroniza el catálogo y termina bien (también si ya estaba sincronizado)" do
    2.times do
      output, status = run("access:sync")

      expect(status).to be_success, output
      expect(output).to include("Catálogo de acceso sincronizado")
    end
  end

  it "db:migrate encadena access:sync" do
    output, status = run("runner", 'Rails.application.load_tasks; puts Rake::Task["db:migrate"].actions.size')
    expect(status).to be_success, output

    # Rails define 1 acción en db:migrate; la nuestra es la segunda.
    expect(output.lines.last.to_i).to be >= 2
  end
end
