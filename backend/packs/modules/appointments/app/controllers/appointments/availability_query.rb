module Appointments
  # Reads and shapes the query of an availability request, for the panel and the public controllers. A missing parameter is a
  # 400 `request.invalid`; one that is not the shape asked for is a 400 `request.bad_request`. `typed_params` only reads the
  # body, so the query is parsed here.
  module AvailabilityQuery
    QUERY_PARAMS = %w[service_ids professional_id from to].freeze
    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/
    # Ten ids with their commas: room to let the use case report "too many" for a short overlong list, a bound for a hostile one.
    MAX_SERVICE_IDS_LENGTH = 10 * 37

    private

    # { service_ids: [uuid...] in the requested order, professional_id: uuid or :any, from:, to: } plus each of `extra_uuids`
    # (further required parameters that are UUIDs, such as the branch where the route does not name it), keyed by symbol.
    def availability_query(extra_uuids: [])
      names = QUERY_PARAMS + extra_uuids.map(&:to_s)
      reject_repeated_query_params(names)
      values = names.index_with { required_query_param(it) }
      { service_ids: uuid_list(values["service_ids"], :service_ids), professional_id: professional_param(values["professional_id"]),
        from: date(values["from"], :from), to: date(values["to"], :to) }
        .merge(extra_uuids.to_h { |name| [ name, uuid(values[name.to_s], name) ] })
    end

    # Rack keeps the last value of a repeated parameter and the rest vanish silently; the raw query string still shows them.
    def reject_repeated_query_params(names)
      raw = Rack::Utils.parse_query(request.query_string)
      repeated = names.find { raw[it].is_a?(Array) }
      raise ActionController::BadRequest, "#{repeated} must be a single value" if repeated
    end

    def required_query_param(name)
      value = params[name]
      raise ActionController::ParameterMissing, name if value.blank?
      raise ActionController::BadRequest, "#{name} must be a single value" unless value.is_a?(String)

      value
    end

    def uuid_list(value, name)
      raise ActionController::BadRequest, "#{name} is too long" if value.length > MAX_SERVICE_IDS_LENGTH

      value.split(",", -1).map { uuid(it, name) }
    end

    def professional_param(value) = value == "any" ? :any : uuid(value, :professional_id)

    def uuid(value, name)
      raise ActionController::BadRequest, "#{name} must be a UUID" unless UUID_FORMAT.match?(value)

      value.downcase
    end

    def date(value, name)
      raise ActionController::BadRequest, "#{name} must be a date as YYYY-MM-DD" unless DATE_FORMAT.match?(value)

      Date.strptime(value, "%Y-%m-%d")
    rescue Date::Error
      raise ActionController::BadRequest, "#{name} must be a valid date as YYYY-MM-DD"
    end
  end
end
