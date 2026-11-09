module Idempotency
  # Otra petición con la misma Idempotency-Key sigue en curso y no terminó dentro de la espera acotada. La API responde
  # 409 idempotency.request_in_progress: el cliente reintenta con la MISMA clave y recibe la respuesta guardada.
  class RequestInProgress < Error; end
end
