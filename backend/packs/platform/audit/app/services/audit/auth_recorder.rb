module Audit
  class AuthRecorder
    def self.call(action:, user_id:, ip:, user_agent:, metadata:)
      raise ArgumentError, "action es obligatoria" if action.blank?

      AuthEvent.create!(
        action: action.to_s, user_id:, request_id: Current.request_id, ip: ip || Current.ip,
        user_agent: (user_agent || Current.user_agent)&.truncate(Recorder::USER_AGENT_LIMIT, omission: ""),
        metadata: metadata.as_json, created_at: Time.current
      )
    end
  end
end
