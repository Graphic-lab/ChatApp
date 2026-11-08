# Heart to Heart

Private chat-app voor iPhone. Spreek in je eigen taal. De ander leest en hoort jouw bericht in de zijne.
Vertaling en stem gebeuren op het toestel zelf via Apple. Er zijn geen kosten per bericht.

- Spraakberichten: houd de microfoon ingedrukt, of tik om te starten en te stoppen
- Automatische vertaling en voorlezen bij de ontvanger
- Contacten, groepen, blokkeren
- Alleen op uitnodiging. Eén owner die door niemand verwijderd of geblokkeerd kan worden.
- Native SwiftUI met Liquid Glass (iOS 26+) en fallback vanaf iOS 18

## Repo

| Map | Inhoud |
|---|---|
| [`specs/`](specs/) | Spec-driven design: [requirements](specs/requirements.md), [design](specs/design.md), [tasks](specs/tasks.md), [beslissingen](specs/decisions/README.md) |
| [`buildkit/`](buildkit/) | [Stappenplan](buildkit/README.md) en scripts: `check-env.sh`, `bootstrap.sh`, `verify.sh` |
| [`ios/`](ios/) | De app (XcodeGen: `project.yml`) |
| [`supabase/`](supabase/) | Migraties en tests van de databaseregels |
| [`_prompt/`](_prompt/) | AI-werkcontract (geladen via `CLAUDE.md`) |

## Snel starten

```bash
buildkit/check-env.sh
buildkit/bootstrap.sh
buildkit/verify.sh
```

Volledige uitleg: [buildkit/README.md](buildkit/README.md).

De web-POC (`heart-to-heart-ukrainian-dutch`, Lovable) is een aparte repo en staat niet in deze repo.
