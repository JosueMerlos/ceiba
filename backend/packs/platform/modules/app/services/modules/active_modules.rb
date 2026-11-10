module Modules
  # A company's ACTIVE modules with settings already resolved (default -> company -> context branch), for /me. At most two
  # queries (company_modules rows and branch overrides), however many modules there are.
  module ActiveModules
    Entry = Data.define(:manifest, :settings)

    # Stored data can stop satisfying the schema (incompatible change, corrupt data) and /me must not break over ONE module:
    # degrade gradually and REPORT. An invalid BRANCH override falls back to the company level; if that is invalid too, to the
    # schema defaults (the module stays active).
    def resolve(manifest, row, branch_row)
      SettingsResolver.call!(manifest, row.settings, branch_row&.settings)
    rescue InvalidSettings => error
      report(error, manifest, row, branch_row)
      branch_row ? resolve(manifest, row, nil) : manifest.defaults.deep_dup
    end

    def report(error, manifest, row, branch_row)
      context = { module: manifest.key, company_id: row.company_id, branch_id: branch_row&.branch_id }.compact
      Rails.error.report(error, handled: true, severity: :error, context:)
    end
    module_function :resolve, :report
    private_class_method :resolve, :report

    module_function

    def call(company:, branch: nil)
      rows = CompanyModule.active.where(company_id: company.id).to_a
      branch_settings = branch ? BranchModuleSetting.where(branch_id: branch.id).index_by(&:module_key) : {}
      rows.filter_map do |row|
        # Skip rows of modules whose manifest no longer exists (removed from the code).
        next unless Modules.registry.key?(row.module_key)

        manifest = Modules.registry.fetch(row.module_key)
        Entry.new(manifest:, settings: resolve(manifest, row, branch_settings[row.module_key]))
      end.sort_by { |entry| entry.manifest.key }
    end
  end
end
