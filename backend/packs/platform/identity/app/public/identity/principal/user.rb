module Identity
  module Principal
    # Who acts in the panel: the person authenticated by a session. MINIMAL on purpose: identity only. Memberships,
    # permissions and `can?(permission, scope)` are not here (see Access::Principal); do not infer authorization from
    # this object.
    User = Data.define(:id, :email, :full_name) do
      def actor_type = "user"
    end
  end
end
