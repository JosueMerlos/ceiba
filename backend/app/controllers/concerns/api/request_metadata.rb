module Api
  # Request data for the audit trail (request_id, IP, user agent), stored in Current. Included before authentication so
  # login has it too. `remote_ip` honors the trusted proxy: X-Forwarded-For is never read by hand.
  module RequestMetadata
    extend ActiveSupport::Concern

    included do
      before_action :capture_request_metadata
    end

    private

    def capture_request_metadata
      Current.request_id = request.request_id
      Current.ip = request.remote_ip
      Current.user_agent = request.user_agent
    end
  end
end
