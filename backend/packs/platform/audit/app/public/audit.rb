# API pública del pack platform/audit (junto con los errores de dominio). ADR-0022.
module Audit
  # Registra quién hizo qué, con el antes y el después, en `audit_events` (append-only por trigger de PostgreSQL).
  #
  #   Audit.record(action: "organization.updated", subject: organization,
  #                before: { "name" => "A" }, after: { "name" => "B" }, metadata: { "reason" => "rename" })
  #
  # - Exige un contexto de tenancy (Tenancy.with_context): el evento pertenece a la organización del contexto. Sin él
  #   lanza Audit::NoContext y no escribe nada.
  # - Es una escritura más de la transacción del llamador: si hace rollback, el evento desaparece con el cambio.
  # - El actor sale de `actor:` o, si falta, de Current.principal / el principal del contexto; sin principal es `system`.
  #   Un principal declara su tipo con `actor_type` (user, api_key, platform_staff...); sin él se deriva del nombre de la clase.
  # - `before:`/`after:` son hashes de atributos; se guarda el DIFF (solo lo que cambió) con los campos sensibles
  #   enmascarados como "[FILTERED]" (mismo criterio que filter_parameters, recursivo) y con la PII cifrada del sujeto
  #   también como "[FILTERED]" (Audit::Diff).
  #   Una creación pasa solo `after:`; un borrado, solo `before:`.
  # - request_id, IP y user agent salen de Current (los fija Api::RequestMetadata en cada request de la API).
  def self.record(action:, subject:, before: nil, after: nil, metadata: {}, actor: nil)
    Recorder.call(action:, subject:, before:, after:, metadata:, actor:)
  end

  # Registra un evento de identidad (login, logout, revocación) en `auth_audit_events`. Estos eventos NO tienen
  # organización (users y sessions son globales, ADR-0028; un login fallido con un correo sin cuenta no pertenece a
  # ninguna), por eso van a una tabla global aparte y no requieren contexto de tenancy.
  #
  #   Audit.record_auth(action: "auth.login_failed", user_id: user&.id, ip: request.remote_ip, user_agent: request.user_agent,
  #                     metadata: { "email_digest" => digest })
  #
  # NUNCA pases contraseñas ni tokens en `metadata:`. ip y user agent, si faltan, salen de Current.
  def self.record_auth(action:, user_id: nil, ip: nil, user_agent: nil, metadata: {})
    AuthRecorder.call(action:, user_id:, ip:, user_agent:, metadata:)
  end
end
