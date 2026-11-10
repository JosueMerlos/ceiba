export const shell = {
  skipLink: "Saltar al contenido",
  navigation: "Navegación principal",
  userMenu: "Cuenta de {{name}}",
  context: {
    menuLabel: "Cambiar el contexto de trabajo",
    organization: "Organización",
    company: "Empresa",
    branch: "Sucursal",
    allBranches: "Todas las sucursales",
    suspended: "{{name}} (suspendida)",
    loadError: "No se pudo cargar el contexto de trabajo.",
  },
  nav: {
    agenda: "Agenda",
    summary: "Resumen de citas",
  },
  noContext: {
    title: "Todavía no tiene acceso a ninguna empresa",
    description:
      "Su cuenta existe, pero aún no tiene un rol asignado. Pida a quien administra su organización que le dé acceso.",
  },
  home: {
    title: "Inicio",
    greeting: "Hola, {{name}}",
    workingIn: "Trabajando en {{company}}",
    inBranch: "Sucursal: {{branch}}",
    noModules: "Su empresa todavía no tiene módulos activos.",
  },
} as const;
