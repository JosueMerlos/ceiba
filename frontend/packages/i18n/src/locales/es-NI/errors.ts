export const errors = {
  generic: "Ocurrió un problema. Intente de nuevo en unos minutos.",
  network: "No hay conexión con el servidor. Revise su internet e intente de nuevo.",
  sessionExpired: "Su sesión venció. Ingrese de nuevo para continuar.",
  conflict: "La información cambió mientras trabajaba. Se actualizó para que la revise de nuevo.",
  forbidden: {
    title: "No tiene permiso para ver esto",
    description:
      "Su rol no incluye esta sección. Si la necesita, pida acceso a quien administra su cuenta.",
  },
  notFound: {
    title: "No encontramos esta página",
    description: "La dirección no existe o su empresa no tiene activado este módulo.",
  },
  unexpected: {
    title: "Algo salió mal",
    description: "No pudimos mostrar esta pantalla. Ya quedó registrado; intente de nuevo.",
  },
  // Mensajes por `code` de la API (problem+json). El frontend decide por `code`, nunca por el `message` del servidor.
  code: {
    "auth.invalid_credentials": "El correo o la contraseña no son correctos.",
    "auth.csrf_invalid": "La verificación de seguridad venció. Recargue la página e intente de nuevo.",
    "auth.origin_forbidden": "La solicitud no vino de la aplicación. Recargue la página.",
    "rate_limited": "Demasiados intentos seguidos. Espere un momento e intente de nuevo.",
    "access.organization_suspended": "Esta organización está suspendida. Contacte a soporte.",
    "slot.unavailable": "El horario ya no está disponible. Elija otro.",
  },
} as const;
