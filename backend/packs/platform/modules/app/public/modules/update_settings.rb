module Modules
  # Writes a module's settings for a company or, with `branch:`, for a branch. Each value is validated against the module's
  # JSON Schema; an invalid value, a key the schema does not define or a key not allowed at branch level raises
  # Modules::InvalidSettings with per-field detail (422 in the API) and saves NOTHING.
  #
  #   Modules::UpdateSettings.call(company:, key: "appointments", settings: { "min_lead_time_minutes" => 60 }, branch:)
  #
  # `settings` holds ONLY the keys to change (merged with earlier overrides of the same level); a `nil` value removes the
  # override and falls back to the higher level. Returns that level's resolved settings. Requires the module active (NotEnabled).
  class UpdateSettings
    def self.call(company:, key:, settings:, branch: nil) = new(company:, key:, settings:, branch:).call

    def initialize(company:, key:, settings:, branch:)
      raise ArgumentError, "settings debe ser un Hash (recibió #{settings.class})" unless settings.respond_to?(:to_h) && !settings.is_a?(Array)
      raise ArgumentError, "la sucursal #{branch.id} no es de la empresa #{company.id}" if branch && branch.company_id != company.id

      @company = company
      @branch = branch
      @manifest = Modules.registry.fetch(key)
      @changes = settings.to_h.stringify_keys
    end

    def call
      ApplicationRecord.transaction(requires_new: true) do
        company_row = CompanyModule.active.lock.find_by(company_id: @company.id, module_key: @manifest.key)
        raise NotEnabled, @manifest.key unless company_row

        reject_unknown_or_not_allowed!
        @branch ? update_branch(company_row) : update_company(company_row)
      end
    end

    private

    def update_company(row)
      previous = row.settings
      overrides = merge(previous)
      resolved = SettingsResolver.call!(@manifest, overrides)
      row.update!(settings: overrides)
      audit(row, previous, overrides, level: "company")
      resolved
    end

    def update_branch(company_row)
      row = BranchModuleSetting.lock.find_or_initialize_by(branch_id: @branch.id, module_key: @manifest.key)
      previous = row.settings
      overrides = merge(previous)
      resolved = SettingsResolver.call!(@manifest, company_row.settings, overrides)
      row.update!(company_id: @company.id, settings: overrides)
      audit(row, previous, overrides, level: "branch", branch_id: @branch.id)
      resolved
    end

    def merge(current) = current.merge(@changes).compact

    def reject_unknown_or_not_allowed!
      errors = @changes.each_key.filter_map do |name|
        if @manifest.setting_keys.exclude?(name)
          error(name, "unknown")
        elsif @branch && !@manifest.overridable_at?(:branch, name)
          error(name, "not_allowed_at_level")
        end
      end
      raise InvalidSettings.new(@manifest.key, errors) if errors.any?
    end

    def error(field, code) = { field:, code:, message: I18n.t("modules.settings_errors.#{code}") }

    # Audits only the touched keys, old and new value, in the same transaction. Property names cannot be sensitive (the
    # manifest forbids it), so Audit::Diff's masking never hides a value.
    def audit(row, previous, current, **scope)
      return if previous == current

      keys = previous.keys | current.keys
      Audit.record(
        action: "module.settings_updated", subject: row, before: previous.slice(*keys), after: current.slice(*keys),
        metadata: { "module" => @manifest.key, "company_id" => @company.id, **scope.stringify_keys }
      )
    end
  end
end
