require "rails_helper"
require "ci/policy_permissions"
require "tmpdir"

# El escáner debe ver lo que el ojo humano no: permisos no literales, literales con #{} y comentarios al final de línea.
RSpec.describe PolicyPermissions, "#violations" do
  let(:root) { Pathname(Dir.mktmpdir("ceiba-policy-literals")) }

  after { FileUtils.remove_entry(root) }

  def violations_for(body, registered: [ "platform.thing.read" ])
    file = root.join("packs/platform/x/app/policies/x/thing_policy.rb")
    FileUtils.mkdir_p(file.dirname)
    File.write(file, body)
    described_class.new(root).violations(registered:)
  end

  it "una llamada a can? con un argumento que no es literal es una violación (no se puede verificar)" do
    out = violations_for(%(class X::ThingPolicy < Access::BasePolicy\n  def show? = can?(permission_for(record), scope)\nend\n))

    expect(out).to contain_exactly(a_string_matching(/thing_policy.rb:2: .*literal/))
  end

  it "lo mismo con reach y con can? sin paréntesis o con variable" do
    out = violations_for(%(class X::ThingPolicy < Access::BasePolicy\n  def a? = can? KEY, scope\n  def b = reach(key)\nend\n))

    expect(out.size).to eq(2)
  end

  it "un literal con interpolación en la clave no cuenta como literal" do
    out = violations_for(%q(class X::ThingPolicy < Access::BasePolicy
  def show? = can?("platform.#{kind}.read", scope)
end
))

    expect(out).to contain_exactly(a_string_matching(/literal/))
  end

  it "un literal con # dentro de una interpolación no corta el resto de la línea" do
    out = violations_for(%q(class X::ThingPolicy < Access::BasePolicy
  def show? = [ "#{record.name}", can?("platform.otro.cosa", scope) ].all?
end
))

    expect(out).to contain_exactly(a_string_matching(/platform\.otro\.cosa/))
  end

  it "ignora comentarios y no marca llamadas con literal registrado" do
    out = violations_for(%(class X::ThingPolicy < Access::BasePolicy\n  # can?(algo_dinamico) en un comentario\n  def show? = can?("platform.thing.read", scope) # ok\nend\n))

    expect(out).to be_empty
  end
end
