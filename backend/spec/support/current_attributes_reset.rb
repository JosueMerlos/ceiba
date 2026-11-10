# Reinicio global del estado "de request" entre ejemplos. Rails lo reinicia solo al terminar una request o un job, pero un
# spec que abre `Tenancy.with_context` o asigna `Current.principal` sin pasar por una request deja ese estado vivo para el
# siguiente (ActiveSupport::CurrentAttributes no se reinicia en los specs de servicios): `--seed 5718` hacía fallar a
# spec/services/observability/log_fields_spec.rb con un organization_id ajeno. Se limpia DESPUÉS de cada ejemplo (un `after`
# no pisa los `around`/`before` que preparan el contexto de su propio spec).
RSpec.configure do |config|
  config.after do
    ActiveSupport::CurrentAttributes.descendants.each(&:reset)
    ActsAsTenant.current_tenant = nil
  end
end
