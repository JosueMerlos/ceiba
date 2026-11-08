require_relative "../../lib/tenant_guard_installer"

ActiveSupport.on_load(:active_record) { TenantGuardInstaller.install! }
