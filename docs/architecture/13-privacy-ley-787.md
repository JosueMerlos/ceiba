# 13 — Privacidad: Ley 787 (Nicaragua)

> Decisión: [ADR-0024](../adr/0024-mercado-nicaragua.md). Hitos: M3.01 (consentimientos), M4.05 (aviso, exportación, supresión).
> **Aviso:** este documento traduce obligaciones legales a diseño técnico y **no es asesoría legal**. Antes de los pilotos (F5), un abogado nicaragüense debe revisar el aviso de privacidad, el acuerdo con los negocios y la interpretación de los artículos citados. Las referencias a artículos provienen de fuentes secundarias y deben confirmarse con el texto oficial.

## Marco

- **Ley No. 787**, Ley de Protección de Datos Personales (2012).
- **Decreto No. 36-2012**, su reglamento (publicado en La Gaceta No. 200, 19 de octubre de 2012).

Puntos que el diseño debe soportar (según las fuentes revisadas):

| Obligación | Referencia (a confirmar) | Diseño |
| --- | --- | --- |
| Consentimiento del titular para tratar y entregar datos, salvo excepción legal | Ley 787, art. 6 | Consentimiento registrado por **finalidad** |
| Archivos de datos lícitos solo si se autorizan y registran, con consentimiento | Ley 787, art. 4 | Inventario de datos y finalidades; registro ante la autoridad si aplica (**a verificar con el abogado**) |
| Consentimiento tácito permitido salvo que la ley exija uno expreso; si es expreso, medio sencillo y gratuito | Reglamento, art. 5 | Checkbox explícito en la reserva para los recordatorios; sin costo |
| Demostrar que el titular autorizó el uso para una finalidad específica | Reglamento, art. 11 | Tabla `consents` con evidencia (fuente, fecha, versión del aviso, IP) |
| Revocación del consentimiento en cualquier momento | Reglamento, art. 12 | Revocar con 1 clic desde el mensaje o el enlace; respuesta "STOP" en WhatsApp |
| Derechos del titular (acceso, rectificación, supresión) | Ley 787 (derechos ARCO) | Exportación y anonimización por cliente (M4.05) |

## Roles: quién es responsable del dato

| Actor | Rol (propuesto, a validar legalmente) |
| --- | --- |
| La **empresa** cliente (la barbería, la clínica) | **Responsable** del tratamiento de los datos de *sus* clientes finales |
| La **plataforma** | **Encargado** del tratamiento: procesa por cuenta de la empresa según el contrato |
| La plataforma, para los datos de los **usuarios del staff** | Responsable |

Consecuencia: el **acuerdo de tratamiento de datos** con cada organización es un documento necesario antes del piloto (F5), no un detalle.

## Diseño técnico

### Consentimientos (M3.01)

```
consents
  id, organization_id, company_id, customer_id,
  purpose        -- 'appointment_reminders' | 'marketing' (futuro) | …
  channel        -- 'whatsapp' | 'email' | NULL (todas)
  granted_at, revoked_at NULL,
  source         -- 'public_booking' | 'staff_entry' | 'import' | 'whatsapp_reply'
  notice_version -- versión del aviso de privacidad aceptado
  evidence JSONB -- ip, user_agent, actor_id (si lo registró el staff)
```

- **Append-only lógico:** revocar crea `revoked_at`; volver a otorgar crea una fila nueva. El historial es la evidencia.
- `Notifications.deliver` **consulta el consentimiento vigente** para (cliente, finalidad, canal) antes de enviar. Sin consentimiento → no se envía y se registra el motivo en el delivery log.
- Los recordatorios de cita son la finalidad `appointment_reminders`. El marketing, si llega a existir, es una finalidad **separada** que nunca se infiere de la otra.
- Cuando el staff registra a un cliente, indica cómo obtuvo el consentimiento (`staff_entry`), y queda auditado.
- En la importación CSV, los clientes importados **no** tienen consentimiento salvo que se marque explícitamente con la fuente; por defecto no reciben recordatorios.

### Aviso de privacidad (M4.05)

- Versionado (`privacy_notices(version, body, published_at)`); la versión aceptada se guarda en cada consentimiento.
- Visible en la página pública de reserva antes de confirmar y enlazado en cada mensaje.
- Plantilla base de la plataforma, personalizable con los datos del responsable (la empresa).

### Derechos del titular (M4.05)

| Derecho | Implementación |
| --- | --- |
| Acceso | Exportación JSON/CSV de los datos del cliente en una empresa (staff con permiso, por solicitud) |
| Rectificación | Edición desde el panel, auditada |
| Supresión | **Anonimización** del cliente: se borran nombre, teléfono, correo y notas; las citas quedan como "cliente eliminado" para conservar conteos e historial operativo |
| Revocación | Desde el enlace del mensaje, "STOP" en WhatsApp o el panel |

Cada solicitud queda registrada (`data_subject_requests`) con la fecha de recepción y la de resolución.

### Minimización

- Los datos mínimos del cliente para reservar son nombre y teléfono. El correo es opcional.
- **Sin datos de salud en `appointments`.** Las notas de la cita son operativas. El historial clínico será un módulo aparte con cifrado, consentimiento específico y acceso restringido.
- Los reportes consolidados de la organización muestran solo conteos.
- Los logs no contienen PII (`filter_parameters`, sin cuerpos de request).

### Menores de edad

- Pendiente de definición legal (P2): si un menor puede ser cliente (pediatría, cortes infantiles), el consentimiento lo otorga el tutor. Modelo propuesto: `customers.guardian_customer_id`. No entra al MVP; se revisa con el abogado antes de F5.

## Checklist antes de los pilotos

- [ ] Revisión legal del aviso de privacidad y del acuerdo de tratamiento de datos.
- [ ] Confirmar si se requiere inscripción o registro de archivos ante la autoridad competente.
- [ ] Consentimiento por finalidad funcionando y bloqueando envíos (M3.01).
- [ ] Revocación con 1 clic y por "STOP" (M3.03).
- [ ] Exportación y anonimización de cliente (M4.05).
- [ ] Inventario de datos personales y finalidades publicado en `docs/`.
