module Modules
  # "Last used context" of GET /api/v1/me: a SIGNED per-browser cookie with `organization:company:branch`. Not persisted in the
  # database because (1) a GET does not write (it runs in a read-only transaction) and (2) the remembered context is a
  # per-device convenience, not user data. It is NOT a credential: it is re-validated against memberships on every use (a user
  # who lost access falls back to the default context) and a tampered cookie is ignored.
  module ContextCookie
    BASE_NAME = "ceiba_context".freeze
    LIFETIME = 90.days
    SEPARATOR = ":".freeze

    # The cookie is bound to the user (their id inside the signed value): someone else logging in on the same browser does not
    # inherit the previous context, and a cookie left after a logout is useless to anyone else.
    Selection = Data.define(:organization_id, :company_id, :branch_id) do
      def serialize = [ organization_id, company_id, branch_id ].map(&:to_s).join(SEPARATOR)
    end

    module_function

    def name = Api::SessionCookie.secure? ? "#{Api::SessionCookie::HOST_PREFIX}#{BASE_NAME}" : BASE_NAME

    # Nil when absent, tampered, from another user or with non-UUID ids.
    def read(cookies, user_id:)
      value = cookies.signed[name]
      return unless value.is_a?(String)

      owner, organization_id, company_id, branch_id = value.split(SEPARATOR, -1).map(&:presence)
      return unless owner == user_id.to_s && organization_id && [ organization_id, company_id, branch_id ].compact.all? { |id| id.match?(/\A[0-9a-f-]{36}\z/) }

      Selection.new(organization_id:, company_id:, branch_id:)
    end

    # Writes only on change, to avoid a Set-Cookie on every request.
    def write(cookies, selection, user_id:)
      return if read(cookies, user_id:) == selection

      cookies.signed[name] = Api::SessionCookie.attributes.merge(value: "#{user_id}#{SEPARATOR}#{selection.serialize}", expires: LIFETIME.from_now)
    end
  end
end
