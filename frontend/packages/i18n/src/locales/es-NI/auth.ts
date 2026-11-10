export const auth = {
  welcome: "Hola, {{name}}",
  login: {
    title: "Iniciar sesión",
    intro: "Ingrese con su correo y contraseña para ver la agenda de su negocio.",
    email: "Correo electrónico",
    emailPlaceholder: "nombre@negocio.com",
    password: "Contraseña",
    showPassword: "Mostrar contraseña",
    hidePassword: "Ocultar contraseña",
    submit: "Entrar",
    submitting: "Entrando…",
    emailRequired: "Escriba su correo electrónico",
    emailInvalid: "Revise el correo: debe tener la forma nombre@dominio.com",
    passwordRequired: "Escriba su contraseña",
    tagline: "Las citas de su negocio, en orden y a la sombra.",
  },
  logout: "Cerrar sesión",
  logoutAll: "Cerrar sesión en todos los dispositivos",
  logoutAllDialog: {
    title: "¿Cerrar sesión en todos los dispositivos?",
    description:
      "Se cerrará su sesión en este y en cualquier otro dispositivo donde haya ingresado. Tendrá que volver a entrar.",
    confirm: "Cerrar todas las sesiones",
  },
} as const;
