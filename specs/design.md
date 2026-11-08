# Design — Heart to Heart (iOS)

## Architectuur

```
iPhone (SwiftUI, iOS 18+)                      Supabase (eigen project)
┌───────────────────────────────┐              ┌──────────────────────────────┐
│ Views (Features/*)            │              │ Auth: e-mail OTP             │
│   ↓                           │   HTTPS      │   trigger gate_signup        │
│ SessionStore / ConversationModel ─────────────→ Postgres + RLS + RPC         │
│   ↓                           │   Realtime   │   owner-triggers             │
│ Backend (supabase-swift)      │ ←──────────── │ Realtime: messages           │
│                               │              │ Storage: voice/<conv>/<msg>  │
│ Op toestel:                   │              └──────────────────────────────┘
│  Recorder → SFSpeechRecognizer│
│  AppleTranslator (Translation)│
│  Speaker (AVSpeechSynthesizer)│
└───────────────────────────────┘
```

## Berichtstroom

**Versturen (toestel A)**
1. `RecordingGesture` → `VoiceRecorder` neemt op naar `.m4a`.
2. `Transcriber` zet om naar tekst in de spreektaal van A (`speech_locale` of keuze in het gesprek).
3. Upload naar `voice/<conversation_id>/<message_id>.m4a`.
4. Insert in `messages` met `original_text` en `source_lang`.

**Ontvangen (toestel B)**
1. Een realtime-insert (of een herlaadbeurt bij terugkeer naar de voorgrond) wordt samengevoegd op ID.
2. Als `source_lang ≠ B.language`: `AppleTranslator.translate`, met cache per tekst en taalpaar.
3. Bij automatisch voorlezen: `Speaker` kiest een stem via `VoicePicker` (taal B, geslacht van A, voorkeursregio van B, bv. nl-BE).

**Waarom de ontvanger vertaalt en niet de afzender:** in groepen heeft elk lid een eigen taal. Eén bericht volstaat dan voor iedereen, en het kost niets.

## Datamodel

Zie [`supabase/migrations/0001_core.sql`](../supabase/migrations/0001_core.sql).

| Tabel | Doel |
|---|---|
| `app_config` | Eén rij met `owner_email`. Geen policies: alleen leesbaar via de SQL-editor of de service role. |
| `invites` | E-mailadressen die een account mogen maken (alleen de owner) |
| `profiles` | Naam, taal, spreektaal, stemgeslacht, rol, status |
| `contacts` | Persoonlijke contactlijst |
| `blocks` | Wie wie blokkeert. De owner kan niet geblokkeerd worden (trigger). |
| `conversations` / `conversation_members` | 1-op-1 en groepen. Wijzigingen alleen via RPC. |
| `messages` | Originele tekst, brontaal, audiopad, soft delete |

## Afdwinging (deterministisch)

| Regel | Mechanisme |
|---|---|
| Alleen op uitnodiging | `BEFORE INSERT`-trigger op `auth.users` |
| Owner-bescherming | Triggers `guard_profiles`, `guard_blocks`, `guard_members`, `guard_messages` |
| Lidmaatschap en beheer | `security definer`-RPC's. Er zijn geen directe insert-, update- of delete-policies. |
| Leesrechten | RLS: actief lid én lid van het gesprek |
| Audio | Storage-policies op de eerste map (`conversation_id`) |

Getest in `supabase/tests/rules.test.js` (PGlite, de echte migratie). Elke test verwijst naar R-OWN, R-CON of R-CHAT.

## UI

- `TabView`: Chats · Contacten · Instellingen. Beheer (alleen owner) zit onder Instellingen.
- `Design/Glass.swift`: `.glass(in:tint:interactive:)`
  - gebouwd met Xcode 26+ en draaiend op iOS 26: `glassEffect` (Liquid Glass)
  - anders: `ultraThinMaterial` met een hairline-rand
- `AmbientBackground`: een langzaam bewegende `MeshGradient`, zodat het glas iets te breken heeft.
- Berichtbubbels zijn glas. Je eigen berichten krijgen een accentkleur. De vertaling staat in `.body`, het origineel in `.footnote` en secundair.
- De microfoonknop is interactief glas en wordt rood tijdens het opnemen, met haptics.
- De typografie volgt SF Pro en Dynamic Type. Alleen de titels zijn `.rounded`.

## Cloud-optie (later, T-13)

- `MessageTranslator`-protocol in `Services/Translation.swift`.
- Plan: een Supabase Edge Function `translate-speak`:
  - input: tekst, brontaal, doeltaal, stemgeslacht
  - output: vertaling en een audio-URL
  - de sleutels (DeepL of OpenAI en een TTS-dienst) staan als Supabase secrets, nooit in de app
- Per gebruiker een instelling: "Vertaling: Apple / Cloud".

## Bekende beperkingen

- **Oekraïense mannenstem:** Apple heeft waarschijnlijk alleen een vrouwenstem (niet geverifieerd). Dan valt `VoicePicker` terug op het andere geslacht. De cloud-optie lost dit op.
- **Eerste vertaling:** iOS vraagt eenmalig om het taalpakket te downloaden.
- **Achtergrond:** iOS speelt geen geluid af zonder gebruikersactie als de app gesloten is. Pushmeldingen (T-12) zijn nodig om de gebruiker te waarschuwen.
- **Vertaalcache:** zit alleen in het geheugen en verdwijnt bij het herstarten van de app.
