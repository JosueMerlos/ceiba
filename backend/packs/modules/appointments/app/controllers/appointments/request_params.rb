module Appointments
  # Parsing of the request values the booking and availability controllers share. Each reader raises the 400 the API contract
  # promises: `typed_params` only reads the body and never lists, so these read what it cannot.
  module RequestParams
    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    ISO_8601_WITH_OFFSET = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})\z/
    # Room to let the use case report "too many" for a short overlong list, a bound for a hostile one.
    MAX_LIST_ITEMS = Availability::MAX_SERVICES * 2
    UUID_WITH_SEPARATOR_LENGTH = 37
    private_constant :UUID_FORMAT, :ISO_8601_WITH_OFFSET, :MAX_LIST_ITEMS, :UUID_WITH_SEPARATOR_LENGTH

    private

    def uuid(value, name)
      raise ActionController::BadRequest, "#{name} must be a UUID" unless UUID_FORMAT.match?(value)

      value.downcase
    end

    # A comma separated string (a query) or an array of strings (a body), as UUIDs in the order given.
    def uuid_list(value, name)
      items = value.is_a?(Array) ? checked_array(value, name) : checked_string(value, name)
      items.map { uuid(it, name) }
    end

    def professional_param(value) = value == "any" ? :any : uuid(value, :professional_id)

    # An instant without an offset would silently take the server's zone, so it is rejected.
    def instant(value, name)
      match = ISO_8601_WITH_OFFSET.match(value)
      raise ActionController::BadRequest, "#{name} must be ISO 8601 with seconds and a UTC offset" unless match

      parsed = Time.iso8601(value)
      raise ArgumentError, "calendar overflow" unless same_wall_clock?(parsed, match)

      parsed
    rescue ArgumentError
      raise ActionController::BadRequest, "#{name} must be a valid ISO 8601 instant"
    end

    # Time.iso8601 rolls a day that does not exist (February 30th) into the next month: reading the parsed time back in the
    # offset it was written in must give the same digits.
    def same_wall_clock?(parsed, match)
      offset = match[7]
      written = offset == "Z" ? parsed.getutc : parsed.getlocal(offset)
      [ written.year, written.month, written.day, written.hour, written.min, written.sec ] == match.captures.first(6).map(&:to_i)
    end

    def checked_string(value, name)
      raise ActionController::BadRequest, "#{name} is too long" if value.length > MAX_LIST_ITEMS * UUID_WITH_SEPARATOR_LENGTH

      value.split(",", -1)
    end

    def checked_array(value, name)
      raise ActionController::BadRequest, "#{name} must be a list of UUIDs" unless value.all?(String)
      raise ActionController::BadRequest, "#{name} is too long" if value.size > MAX_LIST_ITEMS

      value
    end
  end
end
