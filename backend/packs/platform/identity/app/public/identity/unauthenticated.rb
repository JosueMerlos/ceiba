module Identity
  # No hay una sesión válida (cookie ausente, desconocida, revocada o vencida). La API responde 401.
  class Unauthenticated < Error; end
end
