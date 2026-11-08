# Alba (serializers de la API, ADR-0012). Convención: UN serializer por representación, en app/serializers/<pack>/.
Alba.backend = :active_support
Alba.inflector = :active_support

# Fechas ISO 8601 en UTC con Z y milisegundos (docs/architecture/07-api-contract.md).
#   attributes created_at: :iso8601
Alba.register_type :iso8601, converter: ->(time) { time.utc.iso8601(3) }, auto_convert: true
