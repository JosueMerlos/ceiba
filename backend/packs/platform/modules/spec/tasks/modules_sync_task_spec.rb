require "rails_helper"
require "open3"

# `bin/rails modules:sync` valida los manifiestos y sincroniza permisos y concesiones (Access.sync!). Es la tarea del paso de
# release: ejecutarla en cada proceso del arranque tendría carreras (docs/milestones M0.09, riesgos).
RSpec.describe "tarea modules:sync" do
  def run(*args)
    Open3.capture2e({ "RAILS_ENV" => "test" }, "bin/rails", *args, chdir: Rails.root.to_s)
  end

  it "valida los manifiestos, sincroniza y lo cuenta" do
    output, status = run("modules:sync")

    expect(status).to be_success, output
    expect(output).to include("Módulos sincronizados").and include("appointments")
  end

  it "delega en access:sync (la salvaguarda de retiradas sigue siendo la de access)" do
    output, status = run("runner", 'Rails.application.load_tasks; puts Rake::Task["modules:sync"].prerequisites.inspect')

    expect(status).to be_success, output
    expect(output.lines.last).to include("access:sync")
  end
end
