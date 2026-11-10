require "pathname"
require "prism"

# Scanner for permissions used in policies: walks packs/*/*/app/policies with Ruby's parser (Prism, not regular
# expressions) and returns:
#   - each permission key (<module>.<resource>.<action>) written as a literal that is NOT registered with
#     Access.register_permissions;
#   - each `can?` / `reach` call whose first argument is NOT a string literal: a computed permission (variable,
#     constant, interpolation, method) cannot be verified and is rejected. A policy's permissions are written in plain sight.
# The suite runs it, so a forgotten (or mistyped) permission breaks the build even if the route using it is never
# exercised. At runtime `can?` also raises Access::UnknownPermission.
class PolicyPermissions
  POLICIES = "packs/*/*/app/policies/**/*.rb".freeze
  KEY = /\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z/
  PERMISSION_CALLS = %i[can? reach].freeze
  NOT_LITERAL = "primer argumento de %<call>s que no es un literal de cadena (el permiso debe poder verificarse)".freeze

  Finding = Data.define(:file, :line, :kind, :detail)

  # Walks a file and collects permission-shaped literals and calls with a dynamic argument.
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

  # "path:line: detail" for each violation.
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
