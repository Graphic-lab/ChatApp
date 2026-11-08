# Tasks

Status: ✅ klaar · 🔲 open · Verificatie tussen haakjes.

## v0.1 — basis (deze commit)

- ✅ T-01 Supabase-schema, RLS, owner-triggers, RPC's (R-AUTH, R-OWN, R-CON, R-CHAT) · (`supabase/tests`: 11/11 slagen)
- ✅ T-02 Storage-bucket `voice` en realtime-publicatie · (niet getest: vraagt een echt Supabase-project)
- ✅ T-03 XcodeGen-project, Supabase SDK 2.49, secrets via xcconfig
- ✅ T-04 Inloggen met e-mailcode, alleen op uitnodiging (R-AUTH-1/2)
- ✅ T-05 Chats-lijst, 1-op-1 starten, realtime en herladen bij de voorgrond (R-CHAT-1, R-SYNC)
- ✅ T-06 Gesprek: opnemen (vasthouden of tikken), transcriptie, upload, tekstberichten (R-VOICE)
- ✅ T-07 Vertalen op het toestel, voorlezen, origineel beluisteren (R-TR-1..5)
- ✅ T-08 Contacten, blokkeren en deblokkeren (R-CON)
- ✅ T-09 Groepen: maken, leden, beheerders, hernoemen, verlaten (R-CHAT-2..4)
- ✅ T-10 Owner-beheer: uitnodigingen, leden (de)activeren, gesprekken verwijderen (R-OWN-5)
- ✅ T-11 Liquid Glass-designlaag met fallback (NF-UI-1)
- Verificatie van v0.1:
  - compileert tegen de iOS 18.2-SDK zonder fouten
  - unit tests 10/10 op macOS
  - **nog niet uitgevoerd:** simulator, toestel, echte Supabase

## Volgende stappen

- 🔲 T-00 **Eerste run op de nieuwe Mac.** Volg `buildkit/README.md` en test op een fysieke iPhone:
  - opnemen
  - vertaling NL ↔ UA
  - voorlezen
  - AirPods
- 🔲 T-12 Pushmeldingen (APNs). Daarvoor nodig:
  - een betaald Apple Developer-account
  - een Edge Function of database-webhook bij een insert in `messages`
  - een tabel `device_tokens`
- 🔲 T-13 Cloud-optie voor vertaling en stem achter `MessageTranslator` (zie design)
- 🔲 T-14 Live gespreksmodus met oortjes (realtime spraak, fase 2)
- 🔲 T-15 App-icoon (1024×1024 in `Assets.xcassets/AppIcon`)
- 🔲 T-16 Vertaalcache bewaren op het toestel (SwiftData)
- 🔲 T-17 Inloggen met Apple (optioneel)
- 🔲 T-18 CI: GitHub Actions met de databasetests en een iOS-build op een macOS-runner
