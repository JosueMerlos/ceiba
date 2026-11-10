# Convention: ONE serializer per representation, in app/serializers/<pack>/.
Alba.backend = :active_support
Alba.inflector = :active_support

# ISO 8601 dates in UTC with Z and milliseconds.
#   attributes created_at: :iso8601
Alba.register_type :iso8601, converter: ->(time) { time.utc.iso8601(3) }, auto_convert: true
