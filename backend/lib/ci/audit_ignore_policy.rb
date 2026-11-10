require "date"
require "yaml"

# CI tooling, not app code: lib/ci is outside autoload_lib (config/application.rb).
# Validates .bundler-audit.yml: each `ignore` entry must sit on its own line with
#   - ID  # revisar: AAAA-MM-DD | motivo: texto
# and the date must not have expired. Never a permanent ignore.
class AuditIgnorePolicy
  COMMENT = /#\s*revisar:\s*(?<date>\S+)\s*\|\s*motivo:\s*(?<reason>\S.*)$/

  def initialize(yaml_text, today: Date.today)
    @text = yaml_text
    @today = today
  end

  def violations
    config = YAML.safe_load(@text)
    return [ "falta la clave ignore (lista, aunque esté vacía)" ] unless config.is_a?(Hash) && config["ignore"].is_a?(Array)

    config["ignore"].filter_map { |id| violation_for(id.to_s) }
  end

  private

  def violation_for(id)
    line = @text.each_line.find { |candidate| candidate.match?(/\A\s*-\s+#{Regexp.escape(id)}\s*(#|\z)/) }
    comment = line&.match(COMMENT)
    return "#{id}: falta '# revisar: AAAA-MM-DD | motivo: ...' en su propia línea de lista" unless comment

    date = parse_date(comment[:date])
    return "#{id}: fecha de revisión inválida '#{comment[:date]}'" unless date

    "#{id}: fecha de revisión vencida (#{date})" if date < @today
  end

  def parse_date(value)
    Date.iso8601(value)
  rescue Date::Error
    nil
  end
end
