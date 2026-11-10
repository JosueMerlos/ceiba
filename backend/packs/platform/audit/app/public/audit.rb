module Audit
  # Records who did what, with before and after, in `audit_events` (append-only via a PostgreSQL trigger).
  #
  #   Audit.record(action: "organization.updated", subject: organization,
  #                before: { "name" => "A" }, after: { "name" => "B" }, metadata: { "reason" => "rename" })
  #
  # - Requires a tenancy context (Tenancy.with_context); raises Audit::NoContext and writes nothing without one.
  # - Part of the caller's transaction: a rollback removes the event along with the change.
  # - Actor: `actor:`, else Current.principal / the context principal, else `system`. A principal declares its type with
  #   `actor_type`.
  # - `before:`/`after:` are attribute hashes; only the DIFF is stored, with sensitive fields and the subject's
  #   encrypted PII as "[FILTERED]" (Audit::Diff). A create passes only `after:`; a delete only `before:`.
  # - request_id, IP and user agent come from Current (set by Api::RequestMetadata).
  def self.record(action:, subject:, before: nil, after: nil, metadata: {}, actor: nil)
    Recorder.call(action:, subject:, before:, after:, metadata:, actor:)
  end

  # Records an identity event (login, logout, revocation) in `auth_audit_events`. These events have NO organization
  # (users and sessions are global; a failed login with an unknown email belongs to none), so they go to a separate
  # global table and need no tenancy context.
  #
  #   Audit.record_auth(action: "auth.login_failed", user_id: user&.id, ip: request.remote_ip, user_agent: request.user_agent,
  #                     metadata: { "email_digest" => digest })
  #
  # NEVER pass passwords or tokens in `metadata:`. ip and user agent default to Current.
  def self.record_auth(action:, user_id: nil, ip: nil, user_agent: nil, metadata: {})
    AuthRecorder.call(action:, user_id:, ip:, user_agent:, metadata:)
  end

  # Stable pseudonym of personal data (e.g. a failed login's email) to correlate events WITHOUT storing it: HMAC-SHA256
  # keyed from secret_key_base. Still pseudonymized personal data (whoever holds the key can confirm an email), not
  # anonymous.
  def self.pseudonymize(value)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.key_generator.generate_key("ceiba/audit/pseudonym", 32), value.to_s)
  end
end
