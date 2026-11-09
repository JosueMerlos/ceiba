module Idempotency
  # Concern de controlador: hace idempotentes las acciones indicadas (docs/architecture/07-api-contract.md#idempotencia).
  #
  #   class AppointmentsController < Api::BaseController
  #     include Idempotency::Idempotent
  #     idempotent :create, required: true
  #   end
  #
  # Con el header `Idempotency-Key`:
  #   - primera vez: ejecuta la acción y, si responde 2xx, guarda la respuesta 24 horas;
  #   - misma clave y mismo método, ruta y cuerpo: NO ejecuta la acción y repite la respuesta guardada
  #     (con `Idempotency-Replayed: true`);
  #   - misma clave y otro método, ruta o cuerpo: 409 `idempotency.key_reused`.
  # La clave es única por organización y principal. Una respuesta que no es 2xx (o una excepción) no consume la clave.
  # `required: true` exige el header (400 `idempotency.key_required`); sin él y sin `required`, la acción se ejecuta normal.
  #
  # Requisitos: el contexto de tenancy ya abierto cuando corre el filtro (declara `idempotent` DESPUÉS del filtro que abre
  # el contexto, p. ej. el around_action de Tenancy.with_context) y, si la acción es autenticada, Current.principal.
  # La carrera de dos peticiones simultáneas la resuelve el índice único: la segunda espera a que la primera termine.
  module Idempotent
    extend ActiveSupport::Concern

    class_methods do
      def idempotent(*actions, required: false)
        around_action(only: actions) { |controller, action| controller.send(:process_idempotently, required, action) }
      end
    end

    private

    def process_idempotently(required, action)
      replay = Processor.call(request:, response:, required:, &action)
      render_replay(replay) if replay
    end

    def render_replay(replay)
      response.set_header("Idempotency-Replayed", "true")
      replay.headers.each { |name, value| response.set_header(name, value) }
      render body: replay.body, status: replay.status, content_type: replay.content_type
    end
  end
end
