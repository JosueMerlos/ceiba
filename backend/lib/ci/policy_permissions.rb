require "pathname"
require "prism"

# Escáner de permisos usados en policies (M0.08, criterio 8): recorre packs/*/*/app/policies con el parser de Ruby (Prism, no
# expresiones regulares) y devuelve:
#   - cada clave de permiso (<modulo>.<recurso>.<accion>) escrita como literal que NO esté registrada con
#     Access.register_permissions;
#   - cada llamada a `can?` / `reach` cuyo primer argumento NO sea un literal de cadena: un permiso calculado (variable,
#     constante, interpolación, método) no se puede verificar y se rechaza. Los permisos de una policy se escriben a la vista.
# Lo ejecuta la suite, así un permiso olvidado (o con typo) rompe el build aunque la ruta que lo usa no se ejercite. En tiempo de
# ejecución `can?` además lanza Access::UnknownPermission.
class PolicyPermissions
  POLICIES = "packs/*/*/app/policies/**/*.rb".freeze
  KEY = /\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z/
  PERMISSION_CALLS = %i[can? reach].freeze
  NOT_LITERAL = "primer argumento de %<call>s que no es un literal de cadena (el permiso debe poder verificarse)".freeze

  Finding = Data.define(:file, :line, :kind, :detail)

  # Recorre un archivo y junta literales con forma de permiso y llamadas con argumento dinámico.
  class Visitor < Prism::Visitor
    attr_reader :keys, :dynamic

    def initialize
      super
      @keys = []
      @dynamic = []
    end

    def visit_string_node(node)
      @keys << [ node.location.start_line, node.unescaped ] if KEY.match?(node.unescaped)
      super
    end

    def visit_call_node(node)
      if PERMISSION_CALLS.include?(node.name)
        first = node.arguments&.arguments&.first
        @dynamic << [ node.location.start_line, node.name ] unless first.is_a?(Prism::StringNode)
      end
      super
    end
  end

  def initialize(root) = @root = Pathname(root)

  # "ruta:línea: detalle" por cada incumplimiento.
  def violations(registered:)
    findings.filter_map do |finding|
      case finding.kind
      when :key then "#{finding.file}:#{finding.line}: #{finding.detail}" unless registered.include?(finding.detail)
      else "#{finding.file}:#{finding.line}: #{finding.detail}"
      end
    end
  end

  def used_permissions = findings.select { |finding| finding.kind == :key }.map(&:detail).uniq

  private

  def findings
    @findings ||= @root.glob(POLICIES).sort.flat_map do |file|
      relative = file.relative_path_from(@root).to_s
      visitor = Visitor.new
      Prism.parse(file.read).value.accept(visitor)
      visitor.keys.map { |line, key| Finding.new(relative, line, :key, key) } +
        visitor.dynamic.map { |line, call| Finding.new(relative, line, :dynamic, format(NOT_LITERAL, call: "#{call}")) }
    end
  end
end
