require "pathname"

# Escáner de permisos usados en policies (M0.08, criterio 8): recorre packs/*/*/app/policies y devuelve cada clave de permiso
# (<modulo>.<recurso>.<accion>) escrita como literal que NO esté registrada con Access.register_permissions. Lo ejecuta la
# suite, así un permiso olvidado (o con typo) rompe el build aunque la ruta que lo usa no se ejercite. En tiempo de ejecución
# `can?` además lanza Access::UnknownPermission.
class PolicyPermissions
  POLICIES = "packs/*/*/app/policies/**/*.rb".freeze
  # Una cadena entre comillas con exactamente tres segmentos snake_case separados por puntos.
  KEY = /["']([a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*)["']/

  def initialize(root) = @root = Pathname(root)

  # "ruta:línea: clave" por cada uso de un permiso que no está en `registered`.
  def violations(registered:)
    occurrences.reject { |_file, _line, key| registered.include?(key) }.map { |file, line, key| "#{file}:#{line}: #{key}" }
  end

  def used_permissions = occurrences.map(&:last).uniq

  private

  def occurrences
    @root.glob(POLICIES).sort.flat_map do |file|
      relative = file.relative_path_from(@root).to_s
      file.each_line.with_index(1).flat_map do |line, number|
        line.sub(/\s#.*\z/, "").scan(KEY).flatten.map { |key| [ relative, number, key ] }
      end
    end
  end
end
