<!-- El título del PR debe seguir conventional commits: tipo(ámbito opcional): asunto
     Ej.: feat(backend): add readiness check · fix(panel): keep filters on reload -->

## Qué cambia y por qué

<!-- Una o dos frases. Enlaza el hito o ADR (p. ej. M0.02, ADR-0013). -->

## Cómo se probó

- [ ] Escribí el test primero (TDD) y lo vi fallar antes de implementar
- [ ] `bin/ci` pasa en local

## Checklist

- [ ] La documentación en `docs/` está actualizada si cambia una decisión o un comportamiento
- [ ] Sin secretos, `.env` ni datos reales en el diff
- [ ] Las migraciones son compatibles hacia atrás (expand/contract), si las hay
