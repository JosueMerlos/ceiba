module Audit
  # Implementación de Audit.record (privada del pack).
  class Recorder
    USER_AGENT_LIMIT = 255

    def self.call(...) = new(...).call

    def initialize(action:, subject:, before:, after:, metadata:, actor:)
      @action = action.to_s
      @subject = subject
      @before = before
      @after = after
      @metadata = metadata
      @actor = actor
    end

    def call
      validate!
      raise NoContext, "Audit.record requiere un contexto de tenancy (Tenancy.with_context)" unless Current.context

      actor = Actor.resolve(@actor)
      diff = Diff.call(before: @before, after: @after, encrypted_attributes: @subject.class.try(:encrypted_attributes))
      Event.create!(
        actor_type: actor.type, actor_id: actor.id, request_id: Current.request_id, ip: Current.ip,
        user_agent: Current.user_agent&.truncate(USER_AGENT_LIMIT, omission: ""), action: @action,
        auditable_type: @subject.class.name, auditable_id: @subject.id, before: diff[:before], after: diff[:after],
        metadata: @metadata.as_json, created_at: Time.current
      )
    end

    private

    def validate!
      raise ArgumentError, "action es obligatoria" if @action.blank?
      raise ArgumentError, "subject debe ser un registro guardado" unless @subject.respond_to?(:id) && @subject.id.present?
    end
  end
end
