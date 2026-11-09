module Access
  # Los memberships de un usuario en la organización activa, con los permisos de sus roles, ya organizados para responder
  # sin tocar la base. UNA consulta (JOIN a role_permissions, LEFT para no perder memberships de roles sin permisos; y a las
  # sucursales de las empresas donde tiene un membership de empresa, para verificar la empresa REAL de cada sucursal).
  # Debe construirse dentro de Tenancy.with_context: el tenant acota la consulta a la organización activa.
  #
  # El Scope que llega a `allows?` lo construye una policy; un alcance de sucursal con la empresa equivocada
  # (`Scope.branch(company_id: A, branch_id: B1)`) NO obtiene los permisos de la empresa A: se comprueba contra las sucursales
  # precargadas y, si no está (creada después de activar), contra la base una sola vez (memorizado).
  class Grants
    NO_KEYS = Set.new.freeze

    COMPANY_BRANCHES = <<~SQL.squish.freeze
      LEFT JOIN branches ON memberships.scope_level = 'company'
        AND branches.organization_id = memberships.organization_id AND branches.company_id = memberships.company_id
    SQL
    PERMISSIONS = "LEFT JOIN role_permissions ON role_permissions.role_id = memberships.role_id".freeze

    def self.load(user_id:, upward_keys: [], branch_company: ->(_branch_id) { })
      rows = Membership.where(user_id:).joins(PERMISSIONS).joins(COMPANY_BRANCHES)
        .pluck(:scope_level, :company_id, :branch_id, Arel.sql("role_permissions.permission_key"), Arel.sql("branches.id"))
      new(rows, upward_keys:, branch_company:)
    end

    def initialize(rows, upward_keys: [], branch_company: ->(_branch_id) { })
      @upward_keys = upward_keys.to_set
      @branch_company = branch_company
      @verified = {}
      @organization_member = false
      @organization_keys = Set.new
      @company_keys = Hash.new { |hash, id| hash[id] = Set.new }
      @upward_company_keys = Hash.new { |hash, id| hash[id] = Set.new }
      @branch_keys = Hash.new { |hash, id| hash[id] = Set.new }
      @company_branches = Hash.new { |hash, id| hash[id] = Set.new }
      @branch_company_ids = {}
      rows.each { |scope_level, company_id, branch_id, key, covered_branch| add(scope_level, company_id, branch_id, key, covered_branch) }
      freeze_state
    end

    def member? = @organization_member || @company_keys.any? || @branch_keys.any?

    def allows?(key, scope)
      return true if @organization_keys.include?(key)

      case scope.level
      when :organization then false
      when :company then company_allows?(key, scope.company_id)
      else branch_allows?(key, scope)
      end
    end

    def sees_company?(company_id)
      @organization_member || @company_keys.key?(company_id) || @branch_company_ids.value?(company_id)
    end

    def sees_branch?(branch_id, company_id)
      @organization_member || @company_keys.key?(company_id) || @branch_keys.key?(branch_id)
    end

    # Empresa de una sucursal con membership de sucursal (o nil).
    def branch_company_id(branch_id) = @branch_company_ids[branch_id]

    # Las claves que el usuario ejerce DENTRO de un contexto (lo que /me le dice al frontend): las de organización, las de la
    # empresa (y la lectura ascendente), las de cualquier membership de sucursal de esa empresa y, con una sucursal elegida, solo las de
    # ESA sucursal. No filtra por módulo (eso lo hace el principal).
    def keys_within(company_id: nil, branch_id: nil)
      keys = @organization_keys.dup
      return keys unless company_id

      keys.merge(@upward_company_keys.fetch(company_id, NO_KEYS))
      if branch_id
        keys.merge(@company_keys.fetch(company_id, NO_KEYS)) if branch_in_company?(branch_id, company_id)
        keys.merge(@branch_keys.fetch(branch_id, NO_KEYS)) if @branch_company_ids[branch_id] == company_id
      else
        keys.merge(@company_keys.fetch(company_id, NO_KEYS))
        @branch_keys.each { |id, branch_keys| keys.merge(branch_keys) if @branch_company_ids[id] == company_id }
      end
      keys
    end

    def reach(key)
      Reach.new(
        organization: @organization_keys.include?(key),
        company_ids: (@company_keys.filter_map { |id, keys| id if keys.include?(key) } +
                      @upward_company_keys.filter_map { |id, keys| id if keys.include?(key) }).uniq,
        branch_ids: @branch_keys.filter_map { |id, keys| id if keys.include?(key) }
      )
    end

    private

    def company_allows?(key, company_id)
      @company_keys.fetch(company_id, NO_KEYS).include?(key) || @upward_company_keys.fetch(company_id, NO_KEYS).include?(key)
    end

    def branch_allows?(key, scope)
      branch_by_company = @company_keys.fetch(scope.company_id, NO_KEYS).include?(key) && branch_in_company?(scope.branch_id, scope.company_id)
      branch_by_membership = @branch_keys.fetch(scope.branch_id, NO_KEYS).include?(key) && @branch_company_ids[scope.branch_id] == scope.company_id
      branch_by_company || branch_by_membership
    end

    # ¿La sucursal es REALMENTE de esa empresa? Precargado para las empresas del usuario; si no, una consulta memorizada.
    def branch_in_company?(branch_id, company_id)
      return true if @company_branches.fetch(company_id, NO_KEYS).include?(branch_id)

      @verified.fetch(branch_id) { @verified[branch_id] = safe_lookup(branch_id) } == company_id
    end

    def safe_lookup(branch_id)
      @branch_company.call(branch_id)
    rescue ActsAsTenant::Errors::NoTenantSet
      nil # sin contexto no se puede verificar: se niega
    end

    # `Hash.new { }` crea entradas al LEER: se fija la forma final y se corta el default para que una consulta por un id
    # desconocido no cambie el estado ni la visibilidad (sees_company? usa key?).
    def add(scope_level, company_id, branch_id, key, covered_branch)
      case scope_level
      when "organization" then @organization_member = true
      when "company"
        @company_keys[company_id]
        @company_branches[company_id] << covered_branch if covered_branch
      when "branch"
        @branch_keys[branch_id]
        @branch_company_ids[branch_id] = company_id
      end
      return unless key

      case scope_level
      when "organization" then @organization_keys << key
      when "company" then @company_keys[company_id] << key
      when "branch"
        @branch_keys[branch_id] << key
        @upward_company_keys[company_id] << key if @upward_keys.include?(key)
      end
    end

    def freeze_state
      [ @company_keys, @upward_company_keys, @branch_keys, @company_branches ].each { |hash| hash.default_proc = nil }
      [ @organization_keys, @company_keys, @upward_company_keys, @branch_keys, @company_branches, @branch_company_ids ].each(&:freeze)
      freeze
    end
  end
end
