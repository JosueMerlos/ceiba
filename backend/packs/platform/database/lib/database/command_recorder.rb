module Database
  # Hace reversibles los helpers en migraciones `change`.
  module CommandRecorder
    def create_tenant_table(*args, &block)
      record(:create_tenant_table, args, &block)
    end
    ruby2_keywords(:create_tenant_table)

    def enable_tenant_rls(*args, &block)
      record(:enable_tenant_rls, args, &block)
    end
    ruby2_keywords(:enable_tenant_rls)

    def disable_tenant_rls(*args, &block)
      record(:disable_tenant_rls, args, &block)
    end
    ruby2_keywords(:disable_tenant_rls)

    private

    def invert_create_tenant_table(args, &block)
      [ :drop_table, args, block ]
    end

    def invert_enable_tenant_rls(args)
      [ :disable_tenant_rls, [ args.first ] ]
    end

    def invert_disable_tenant_rls(args)
      [ :enable_tenant_rls, [ args.first ] ]
    end
  end
end
