module Observability
  # Tenant and principal fields that accompany every log line (requests and jobs). Never PII: identifiers only.
  #
  # Generic on purpose: reads Current.context / Current.principal and, if there is NO live context, the one remembered
  # in Observability::LogContext (the line is written after the `Tenancy.with_context` block ended). One source per
  # call: fields of a live context are never mixed with leftovers of a previous one. A new principal type needs no
  # change here: the type comes from `actor_type`, `kind` or the class name, and the id may be absent (the system
  # principal has none).
  module LogFields
    KEYS = %i[organization_id company_id branch_id principal_type principal_id].freeze

    module_function

    def current
      principal = Current.principal

      tenant.merge(principal_type: principal && principal_type(principal), principal_id: principal.try(:id))
    end

    # request_id and remote_ip: those Api::RequestMetadata left in Current (the same the audit trail records, already
    # sanitized by NetworkTrust). If the request never reached that before_action, the request's own.
    def request(request)
      { request_id: Current.request_id || request.request_id, remote_ip: Current.ip || request.remote_ip }
    end

    def tenant
      context = Current.context
      return { organization_id: context.organization&.id, company_id: context.company&.id, branch_id: context.branch&.id } if context

      { organization_id: LogContext.organization_id, company_id: LogContext.company_id, branch_id: LogContext.branch_id }
    end

    def principal_type(principal)
      (principal.try(:principal_type) || principal.try(:actor_type) || principal.try(:kind) || principal.class.name.demodulize.underscore).to_s
    end
  end
end
