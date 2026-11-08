# Architecture Decision Records

| ADR | Beslissing | Status |
|---|---|---|
| 0001 | Native Swift/SwiftUI in plaats van een wrapper of Expo | Aanvaard 2026-11-08 |
| 0002 | Eigen Supabase-project. De Lovable-backend van de POC blijft ongemoeid. | Aanvaard 2026-11-08 |
| 0003 | Vertaling en stem op het toestel via Apple. Cloud wordt later een optie. | Aanvaard 2026-11-08 |
| 0004 | Verdeling via TestFlight, niet via de publieke App Store | Voorstel |
| 0005 | Owner-rechten afgedwongen in de database, niet in de app | Aanvaard 2026-11-08 |

## 0001 — Native Swift

**Context**

De gebruiker wil Liquid Glass, AirPods-audio en later een live-modus.

**Beslissing**

SwiftUI met deployment target iOS 18. Liquid Glass wordt voorwaardelijk ingeschakeld (`#if compiler(>=6.2)` en `#available(iOS 26)`).

**Gevolg**

- Geen hergebruik van de React-code.
- Wel volledige toegang tot Apple Translation en Speech.

## 0002 — Eigen Supabase

**Context**

Lovable beheert de POC-database. Wijzigingen buiten Lovable zijn verboden (zie de AGENTS.md van de POC).

**Beslissing**

Een nieuw Supabase-project met migraties in deze repo.

**Gevolg**

De POC en de iOS-app delen geen data.

## 0003 — Apple op het toestel

**Context**

Geen kosten per bericht en privacy.

**Beslissing**

De ontvanger vertaalt met het Translation-framework. Voorlezen gebeurt met `AVSpeechSynthesizer`.

**Gevolg**

- De stemmen klinken minder natuurlijk.
- Mogelijk is er geen Oekraïense mannenstem.
- De cloud-optie blijft open (T-13).

## 0004 — TestFlight

**Context**

Het gaat om een kleine, besloten groep.

**Beslissing**

Interne TestFlight-testers.

**Gevolg**

- Er is geen App Review nodig voor interne testers.
- Belangrijk: App Store-richtlijn 1.2 eist voor publieke apps met gebruikerscontent dat gebruikers iedereen kunnen blokkeren en melden. Een owner die niet geblokkeerd kan worden, past daar niet in. Herzie dit vóór een publieke release.

## 0005 — Owner in de database

**Context**

"Niemand kan mij verwijderen of blokkeren" moet gelden, ook bij een aangepaste of kwaadwillige client.

**Beslissing**

Triggers en RLS in Postgres, getest met PGlite.

**Gevolg**

- De SQL-editor en de service role (auth.uid() is null) blijven volledige toegang hebben. Dat is de projecteigenaar zelf.
- Het Supabase-account van de owner is dus de echte "master key". Beveilig het met 2FA.
