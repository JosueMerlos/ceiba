module Access
  # Los memberships de un usuario en la organización activa, con los permisos de sus roles, ya organizados para responder
  # sin tocar la base. Una consulta (JOIN a role_permissions, LEFT para no perder memberships de roles sin permisos).
  # Debe construirse dentro de Tenancy.with_context: el tenant acota la consulta a la organización activa.
  class Grants
    NO_KEYS = Set.new.freeze

    def self.load(user_id:)
      rows = Membership.where(user_id:)
        .joins("LEFT JOIN role_permissions ON role_permissions.role_id = memberships.role_id")
        .pluck(:scope_level, :company_id, :branch_id, Arel.sql("role_permissions.permission_key"))
      new(rows)
    end

    def initialize(rows)
      @organization_member = false
      @organization_keys = Set.new
      @company_keys = Hash.new { |hash, id| hash[id] = Set.new }
      @branch_keys = Hash.new { |hash, id| hash[id] = Set.new }
      @branch_company_ids = {}
      rows.each { |scope_level, company_id, branch_id, key| add(scope_level, company_id, branch_id, key) }
      freeze_state
    end

    def member? = @organization_member || @company_keys.any? || @branch_keys.any?

    def allows?(key, scope)
      return true if @organization_keys.include?(key)
      return false if scope.level == :organization

      @company_keys.fetch(scope.company_id, NO_KEYS).include?(key) ||
        (scope.level == :branch && @branch_keys.fetch(scope.branch_id, NO_KEYS).include?(key))
    end

    def sees_company?(company_id)
      @organization_member || @company_keys.key?(company_id) || @branch_company_ids.value?(company_id)
    end

    def sees_branch?(branch_id, company_id)
      @organization_member || @company_keys.key?(company_id) || @branch_keys.key?(branch_id)
    end

    def reach(key)
      Reach.new(
        organization: @organization_keys.include?(key),
        company_ids: @company_keys.filter_map { |id, keys| id if keys.include?(key) },
        branch_ids: @branch_keys.filter_map { |id, keys| id if keys.include?(key) }
      )
    end

    private

    # `Hash.new { }` crea entradas al LEER: se fija la forma final y se corta el default para que una consulta por un id
    # desconocido no cambie el estado ni la visibilidad (sees_company? usa key?).
    def add(scope_level, company_id, branch_id, key)
      case scope_level
      when "organization" then @organization_member = true
      when "company" then @company_keys[company_id]
      when "branch"
        @branch_keys[branch_id]
        @branch_company_ids[branch_id] = company_id
      end
      return unless key

      case scope_level
      when "organization" then @organization_keys << key
      when "company" then @company_keys[company_id] << key
      when "branch" then @branch_keys[branch_id] << key
      end
    end

    def freeze_state
      [ @company_keys, @branch_keys ].each { |hash| hash.default_proc = nil }
      @organization_keys.freeze
      @company_keys.freeze
      @branch_keys.freeze
      @branch_company_ids.freeze
      freeze
    end
  end
end
