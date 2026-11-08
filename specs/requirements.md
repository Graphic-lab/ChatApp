# Requirements — Heart to Heart (iOS)

Status: v0.1 · Bron: web-POC `heart-to-heart-ukrainian-dutch` + gesprek 2026-11-08
Notatie: EARS ("Wanneer … zal het systeem …"). Elke requirement heeft een ID; tests en taken verwijzen ernaar.

## Doel

Een koppel (en later familie of vrienden) zonder gemeenschappelijke taal praat vlot met elkaar.
Iedereen spreekt in de eigen taal en leest of hoort de ander in de eigen taal.

## Rollen

| Rol | Wie | Rechten |
|---|---|---|
| Owner | Eén persoon, vastgelegd in `app_config.owner_email` | Alles van een lid + uitnodigen, leden (de)activeren, gesprekken en berichten verwijderen. Kan door niemand verwijderd, geblokkeerd of gedegradeerd worden. |
| Lid | Uitgenodigd e-mailadres | Chatten, contacten, groepen, blokkeren |
| Groepsbeheerder | Lid met `is_admin` in een groep | Leden toevoegen/verwijderen (behalve owner), hernoemen |

## Functioneel

### Toegang
- **R-AUTH-1** Wanneer een niet-uitgenodigd e-mailadres zich aanmeldt, zal het systeem de aanmelding weigeren.
- **R-AUTH-2** Het systeem zal inloggen met een 6-cijferige e-mailcode.
- **R-AUTH-3** Wanneer het e-mailadres gelijk is aan `owner_email`, zal het systeem dat account de rol owner geven.

### Owner-bescherming (hard, server-side)
- **R-OWN-1** Het systeem zal verhinderen dat iemand anders dan de owner de owner blokkeert, deactiveert, verwijdert of zijn rol wijzigt.
- **R-OWN-2** Het systeem zal verhinderen dat iemand de owner uit een gesprek verwijdert. Alleen de owner kan zelf vertrekken.
- **R-OWN-3** Het systeem zal verhinderen dat iemand anders dan de owner berichten van de owner verwijdert.
- **R-OWN-4** De owner zal altijd beheerder zijn van elke groep waarin hij zit.
- **R-OWN-5** Alleen de owner kan uitnodigen, leden (de)activeren en gesprekken voor iedereen verwijderen.

### Contacten en blokkeren
- **R-CON-1** Een lid kan een contact toevoegen met het e-mailadres van een bestaand, actief lid.
- **R-CON-2** Een lid kan een contact verwijderen en blokkeren of deblokkeren.
- **R-CON-3** Wanneer B A blokkeert, zal het systeem A beletten berichten te sturen in hun 1-op-1-gesprek en een nieuw gesprek met B te starten.

### Gesprekken en groepen
- **R-CHAT-1** Een lid kan een 1-op-1-gesprek starten. Er bestaat er maximaal één per paar.
- **R-CHAT-2** Een lid kan een groep maken met een naam en contacten. De maker wordt beheerder.
- **R-CHAT-3** Een groepsbeheerder kan leden toevoegen, verwijderen (behalve de owner), beheerders aanduiden en de groep hernoemen.
- **R-CHAT-4** Een lid kan een groep verlaten.
- **R-CHAT-5** Een afzender kan zijn eigen bericht verwijderen. Het bericht wordt dan "Bericht verwijderd" voor iedereen.
- **R-CHAT-6** Niet-leden kunnen een gesprek, de berichten en de audio niet lezen.

### Spraak en vertaling
- **R-VOICE-1** De microfoonknop ondersteunt vasthouden (opnemen tot loslaten) en kort tikken (start, tweede tik stopt).
- **R-VOICE-2** Na de opname zet het toestel spraak om in tekst in de gekozen spreektaal. Waar mogelijk gebeurt dat op het toestel zelf.
- **R-VOICE-3** De afzender kan per gesprek de spreektaal wisselen (bv. NL of EN).
- **R-VOICE-4** Het originele geluid wordt privé opgeslagen. Gespreksleden kunnen het beluisteren.
- **R-TR-1** Wanneer een bericht in een andere taal binnenkomt, zal het toestel van de ontvanger het vertalen naar diens taal met Apple Translation op het toestel.
- **R-TR-2** Het bericht toont de vertaling groot en het origineel klein.
- **R-TR-3** Wanneer automatisch voorlezen aan staat en het gesprek open is, zal het toestel een nieuw bericht voorlezen. De stem volgt het stemgeslacht van de afzender.
- **R-TR-4** Wanneer de vertaling mislukt, toont het systeem het origineel met een waarschuwing.
- **R-TR-5** De vertaalmotor zit achter een interface, zodat later een cloudmotor kan worden ingeschakeld (zie design, "Cloud-optie").

### Betrouwbaarheid
- **R-SYNC-1** Nieuwe berichten komen realtime binnen.
- **R-SYNC-2** Wanneer de app terug naar de voorgrond komt, worden de berichten opnieuw geladen, zodat gemiste realtime-events geen berichten doen verdwijnen.
- **R-SYNC-3** Berichten worden samengevoegd op ID, zonder duplicaten.

## Niet-functioneel

- **NF-UI-1** Native SwiftUI met Liquid Glass op iOS 26+ en systeemmaterialen op iOS 18–25. SF-lettertypes met Dynamic Type, ondersteuning voor donkere modus en VoiceOver-labels.
- **NF-SEC-1** Alle autorisatie wordt afgedwongen in Postgres (RLS, triggers, RPC). De app is niet vertrouwd.
- **NF-SEC-2** Er staan geen geheimen in de repo. De Supabase-sleutels staan in `ios/Config/Secrets.xcconfig` (git-ignored).
- **NF-PRIV-1** Vertaling en voorlezen gebeuren op het toestel. Er gaat geen tekst naar een AI-dienst van derden.
- **NF-COST-1** Er zijn geen kosten per bericht. Vaste kosten: Apple Developer (~€99 per jaar). Het gratis plan van Supabase volstaat voor kleine groepen.
- **NF-DIST-1** De app wordt verdeeld via TestFlight, niet via de publieke App Store (zie ADR-0004).

## Buiten scope (v0.1)

- Pushmeldingen (taak T-12)
- Cloud-vertaling met natuurlijke stemmen (taak T-13)
- Live gespreksmodus met oortjes (taak T-14)
- Android
