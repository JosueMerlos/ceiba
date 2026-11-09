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
    STORED_HEADERS = %w[Location].freeze
    SUCCESS = (200..299)

    Replay = Data.define(:status, :body, :content_type, :headers)

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
      Key.where(principal_key:, key:).expired(now).delete_all
      stored = Key.find_by(principal_key:, key:)
      reservation = reserve(key, now) unless stored
      # Ya existía, o se adelantó otra petición mientras reservábamos: su fila ya está confirmada y se lee.
      stored ||= Key.find_by!(principal_key:, key:) unless reservation
      return replay_of(stored) if stored

      action.call
      finalize(reservation)
      nil
    end

    # nil si otra petición se adelantó (violación única en un savepoint: no aborta la transacción del request).
    def reserve(key, now)
      Key.transaction(requires_new: true) do
        Key.create!(principal_key:, key:, request_fingerprint: fingerprint, expires_at: now + Key::TTL)
      end
    rescue ActiveRecord::RecordNotUnique
      nil
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

    def principal_key
      @principal_key ||= Current.principal ? "#{Actor.type_of(Current.principal)}:#{Current.principal.id}" : "anonymous"
    end

    def fingerprint
      @fingerprint ||= OpenSSL::Digest::SHA256.hexdigest([ request.request_method, request.path, request.raw_post ].join("\n"))
    end
  end
end
