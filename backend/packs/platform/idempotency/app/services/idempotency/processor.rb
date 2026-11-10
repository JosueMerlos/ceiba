module Idempotency
  # Logic of Idempotency::Idempotent (private to the pack). Returns nil if it ran the action (which already rendered) or
  # a Replay.
  #
  # Concurrency: the RESERVATION (INSERT of the key row) and the action run in the same transaction. Two requests with
  # the same key collide on the unique index: the second WAITS for the first to commit or roll back. If it commits, the
  # second gets the unique violation, reads the stored row and replays the response; if it rolls back (the action
  # failed), the reservation vanishes and the second runs. Two actions never run with the same key.
  class Processor
    HEADER = "Idempotency-Key".freeze
    VALID_KEY = /\A[!-~]{1,255}\z/
    # An ANONYMOUS principal (public booking) shares its scope with all anonymous principals of the organization: the
    # key's entropy is the only thing preventing someone from replaying another's response. A UUID (122 random bits) is
    # required.
    ANONYMOUS_KEY = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    STORED_HEADERS = %w[Location].freeze
    SUCCESS = (200..299)
    # How long (seconds) a request waits for another with the same key to finish before answering 409
    # request_in_progress.
    LOCK_TIMEOUT = 5

    Replay = Data.define(:status, :body, :content_type, :headers)

    # SHA-256 of method + path with query + body AS RECEIVED. JSON with another key order is another request (a retrying
    # client resends the same bytes). Multipart never gets here: ApiRequestGuard requires application/json.
    def self.fingerprint(request)
      OpenSSL::Digest::SHA256.hexdigest([ request.request_method, request.fullpath, request.raw_post ].join("\n"))
    end

    def self.call(request:, response:, required:, &action) = new(request:, response:, required:).call(&action)

    def initialize(request:, response:, required:)
      @request = request
      @response = response
      @required = required
    end

    def call(&action)
      key = request.headers[HEADER]
      return validate_missing_key!(&action) if key.nil?
      raise KeyInvalid, "Idempotency-Key inválida" unless VALID_KEY.match?(key)
      raise KeyInvalid, "Un principal anónimo debe usar una Idempotency-Key con formato UUID" if anonymous? && !ANONYMOUS_KEY.match?(key)

      raise MissingContext, "Idempotency::Idempotent requiere un contexto de tenancy" unless Current.context

      Key.transaction { process(key, &action) }
    end

    private

    attr_reader :request, :response

    def validate_missing_key!
      raise KeyRequired, "Falta el header Idempotency-Key" if @required

      yield
      nil
    end

    def process(key, &action)
      now = Time.current
      purge_expired(key, now)
      stored = Key.find_by(principal_key:, key:)
      reservation = reserve(key, now) unless stored
      # It already existed, or another request got ahead while we reserved: its row is committed and is read.
      stored ||= Key.find_by!(principal_key:, key:) unless reservation
      return replay_of(stored) if stored

      action.call
      finalize(reservation)
      nil
    end

    # Replacing an expired row with the same key may wait on another transaction that holds it locked: same bounded
    # wait.
    def purge_expired(key, now)
      Key.transaction(requires_new: true) { with_lock_timeout { Key.where(principal_key:, key:).expired(now).delete_all } }
    end

    # nil if another request got ahead (unique violation in a savepoint: it does not abort the request's transaction).
    # If the other is still running, the INSERT waits; the wait is BOUNDED by `lock_timeout` (only for the duration of
    # the reservation): on expiry, ActiveRecord::LockWaitTimeout => Idempotency::RequestInProgress (409, the client
    # retries).
    def reserve(key, now)
      Key.transaction(requires_new: true) do
        with_lock_timeout { Key.create!(principal_key:, key:, request_fingerprint: fingerprint, expires_at: now + Key::TTL) }
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # On failure the savepoint rolls back and the SET LOCAL with it; on success the previous value is restored by hand.
    def with_lock_timeout
      connection = Key.connection
      previous = connection.select_value("SELECT current_setting('lock_timeout')")
      connection.execute("SELECT set_config('lock_timeout', '#{(LOCK_TIMEOUT * 1000).to_i}ms', true)")
      yield.tap { connection.execute("SELECT set_config('lock_timeout', #{connection.quote(previous)}, true)") }
    rescue ActiveRecord::LockWaitTimeout
      raise RequestInProgress, "Otra petición con la misma Idempotency-Key sigue en curso"
    end

    def replay_of(stored)
      raise KeyReused, "La Idempotency-Key ya se usó con otra petición" unless stored.request_fingerprint == fingerprint

      Replay.new(status: stored.response_status, body: stored.response_body, content_type: stored.content_type, headers: stored.response_headers)
    end

    # Only 2xx responses are kept; any other releases the key so the client can retry.
    def finalize(reservation)
      return reservation.destroy! unless SUCCESS.cover?(response.status)

      reservation.update!(
        response_status: response.status, response_body: response.body, content_type: response.media_type,
        response_headers: STORED_HEADERS.filter_map { |name| [ name, response.headers[name] ] if response.headers[name] }.to_h
      )
    end

    # No principal, or one without its own id (ApiKey and PublicToken for now, System): shares the anonymous scope.
    def anonymous? = Current.principal.nil? || Current.principal.id.nil?

    def principal_key
      @principal_key ||= anonymous? ? "anonymous" : "#{Actor.type_of(Current.principal)}:#{Current.principal.id}"
    end

    def fingerprint
      @fingerprint ||= self.class.fingerprint(request)
    end
  end
end
