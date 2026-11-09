module Idempotency
  # Lógica de Idempotency::Idempotent (privada del pack). Devuelve nil si ejecutó la acción (que ya renderizó) o un Replay.
  #
  # Concurrencia: la RESERVA (INSERT de la fila de la clave) y la acción corren en la misma transacción. Dos peticiones con la
  # misma clave chocan en el índice único: la segunda ESPERA a que la primera confirme o revierta. Si confirma, la segunda
  # recibe la violación única, lee la fila ya guardada y repite la respuesta; si revierte (la acción falló), la reserva
  # desaparece y la segunda se ejecuta. Nunca corren dos acciones con la misma clave.
  class Processor
    HEADER = "Idempotency-Key".freeze
    VALID_KEY = /\A[!-~]{1,255}\z/
    # Un principal ANÓNIMO (reserva pública) comparte alcance con todos los anónimos de la organización: la entropía de la
    # clave es lo único que evita que alguien repita la respuesta de otro. Se exige un UUID (122 bits aleatorios).
    ANONYMOUS_KEY = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    STORED_HEADERS = %w[Location].freeze
    SUCCESS = (200..299)
    # Cuánto espera (segundos) una petición a que termine otra con la misma clave antes de responder 409 request_in_progress.
    LOCK_TIMEOUT = 5

    Replay = Data.define(:status, :body, :content_type, :headers)

    # SHA-256 de método + ruta con query + cuerpo TAL CUAL llegó. Un JSON con otro orden de claves es otra petición (el cliente
    # que reintenta reenvía los mismos bytes). Los multipart no llegan aquí: ApiRequestGuard exige application/json.
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
      # Ya existía, o se adelantó otra petición mientras reservábamos: su fila ya está confirmada y se lee.
      stored ||= Key.find_by!(principal_key:, key:) unless reservation
      return replay_of(stored) if stored

      action.call
      finalize(reservation)
      nil
    end

    # Reemplazar una fila vencida con la misma clave puede esperar a otra transacción que la tiene bloqueada: misma espera acotada.
    def purge_expired(key, now)
      Key.transaction(requires_new: true) { with_lock_timeout { Key.where(principal_key:, key:).expired(now).delete_all } }
    end

    # nil si otra petición se adelantó (violación única en un savepoint: no aborta la transacción del request). Si la otra
    # sigue en curso, el INSERT espera a que termine; la espera está ACOTADA con `lock_timeout` (solo mientras dura la
    # reserva): vencida, ActiveRecord::LockWaitTimeout => Idempotency::RequestInProgress (409, el cliente reintenta).
    def reserve(key, now)
      Key.transaction(requires_new: true) do
        with_lock_timeout { Key.create!(principal_key:, key:, request_fingerprint: fingerprint, expires_at: now + Key::TTL) }
      end
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # Si falla, el savepoint se revierte y con él el SET LOCAL; si sale bien, se restaura el valor previo a mano. Un bloqueo
    # que no cede a tiempo (ActiveRecord::LockWaitTimeout) es Idempotency::RequestInProgress (409: el cliente reintenta).
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

    # Solo las respuestas 2xx se conservan; cualquier otra libera la clave para que el cliente pueda reintentar.
    def finalize(reservation)
      return reservation.destroy! unless SUCCESS.cover?(response.status)

      reservation.update!(
        response_status: response.status, response_body: response.body, content_type: response.media_type,
        response_headers: STORED_HEADERS.filter_map { |name| [ name, response.headers[name] ] if response.headers[name] }.to_h
      )
    end

    # Sin principal, o con uno sin id propio (ApiKey y PublicToken hasta M4.02/M3.04, System): comparte el alcance anónimo.
    def anonymous? = Current.principal.nil? || Current.principal.id.nil?

    def principal_key
      @principal_key ||= anonymous? ? "anonymous" : "#{Actor.type_of(Current.principal)}:#{Current.principal.id}"
    end

    def fingerprint
      @fingerprint ||= self.class.fingerprint(request)
    end
  end
end
