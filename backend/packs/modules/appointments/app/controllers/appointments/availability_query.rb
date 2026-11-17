module Appointments
  # Reads and shapes the query of an availability request, for the panel and the public controllers. A missing parameter is a
  # 400 `request.invalid`; one that is not the shape asked for is a 400 `request.bad_request`. `typed_params` only reads the
  # body, so the query is parsed here.
  module AvailabilityQuery
    include RequestParams

    QUERY_PARAMS = %w[service_ids professional_id from to].freeze

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
  end
end
