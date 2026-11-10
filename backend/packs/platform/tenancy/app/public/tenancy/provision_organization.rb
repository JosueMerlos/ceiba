module Tenancy
  # The ONLY way to create an organization with its first company and first branch (seeds, console, back-office, tests and
  # future self-signup).
  #
  #   result = Tenancy::ProvisionOrganization.call(
  #     organization: { name:, legal_name: },
  #     company:      { name:, slug:, business_type:, currency: },
  #     branch:       { name:, time_zone: }
  #   )
  #   result.organization / result.company / result.branch
  #
  # Optional `extras:` carries data this service does NOT interpret to the hooks, e.g. the owner that access turns into an
  # `org_owner` membership or the plan that sets the default modules. They arrive frozen in `result.extras`. Each hook
  # validates its own and decides whether a missing value is an error.
  #
  #   Tenancy::ProvisionOrganization.call(organization:, company:, branch:, extras: { owner: Identity::ProvisionUser.call(...) })
  #
  # - One transaction: if anything fails (a hook included), nothing is left half-done.
  # - Expected errors are raised as Tenancy::ProvisioningFailed (reserved or taken slug, invalid data). The DATABASE decides
  #   slug uniqueness: if two provisions race, the UNIQUE constraint wins and the loser gets :slug_taken.
  # - `after_provision` hooks: other packs plug in WITHOUT modifying this service (organization owner, default modules). They
  #   run in registration order, inside the transaction and the new organization's context. A raising hook rolls back
  #   EVERYTHING and its error propagates as is.
  class ProvisionOrganization
    Result = Data.define(:organization, :company, :branch, :extras) do
      def initialize(organization:, company:, branch:, extras: {})
        super(organization:, company:, branch:, extras: extras.dup.freeze)
      end
    end

    # The hook registry lives in the application config, NOT in the class: in development the class reloads and a class ivar
    # would lose the hooks. A hook may carry a `key`: registering another with the same key REPLACES it, so
    # `config.to_prepare { ProvisionOrganization.after_provision(Hook, key: :x) }` is idempotent on every reload (and
    # reloadable callables do not go stale).
    STORE = Rails.application.config.x.tenancy

    class << self
      def call(organization:, company:, branch:, extras: {})
        new(organization:, company:, branch:, extras:).call
      end

      # Hook is a lambda, proc or object with #call(result). Returns it so it can be removed.
      def after_provision(callable = nil, key: nil, &block)
        hook = callable || block
        raise ArgumentError, "after_provision requiere un objeto que responda a call (o un bloque)" unless hook.respond_to?(:call)

        update_hooks do |entries|
          index = key && entries.index { |entry| entry.first == key }
          index ? entries.dup.tap { |copy| copy[index] = [ key, hook ] } : entries + [ [ key, hook ] ]
        end
        hook
      end

      def remove_after_provision(hook)
        update_hooks { |entries| entries.reject { |_key, registered| registered.equal?(hook) } }
      end

      def hooks = (STORE.after_provision_hooks || []).map(&:last)

      private

      def update_hooks
        lock.synchronize { STORE.after_provision_hooks = yield(STORE.after_provision_hooks || []).freeze }
      end

      def lock = STORE.after_provision_lock ||= Mutex.new
    end

    def initialize(organization:, company:, branch:, extras: {})
      raise ArgumentError, "extras debe ser un Hash (recibió #{extras.class})" unless extras.is_a?(Hash)

      @extras = extras
      @organization_attributes = AllowedAttributes.permit(organization, AllowedAttributes::ORGANIZATION, :organization)
      @company_attributes = AllowedAttributes.permit(company, AllowedAttributes::COMPANY, :company)
      @branch_attributes = AllowedAttributes.permit(branch, AllowedAttributes::BRANCH, :branch)
    end

    def call
      result = nil
      # requires_new: inside a foreign transaction (tests, a job) a failure rolls back to a savepoint and leaves the
      # connection usable instead of aborting the whole transaction.
      ApplicationRecord.transaction(requires_new: true) do
        result = FailureTranslator.translating(slug: @company_attributes[:slug]) { create_records }.with(extras: @extras)
        # Hooks run in the SAME transaction but OUTSIDE the translator: their error propagates as is (rolling everything
        # back) instead of being disguised as ProvisioningFailed.
        run_hooks(result)
      end
      result
    end

    private

    def create_records
      organization = Organization.create!(@organization_attributes)
      company, branch = Tenancy.with_context(organization:) do
        company = Company.create!(@company_attributes)
        [ company, Branch.create!(@branch_attributes.merge(company:)) ]
      end
      Result.new(organization:, company:, branch:)
    end

    def run_hooks(result)
      Tenancy.with_context(organization: result.organization, company: result.company, branch: result.branch) do
        self.class.hooks.each { |hook| hook.call(result) }
      end
    end
  end
end
