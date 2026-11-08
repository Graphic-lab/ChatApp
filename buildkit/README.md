# Build Kit — van nul tot app op 2 iPhones

Doorlooptijd: ongeveer 1 à 2 uur, exclusief downloads.

## 0. Wat je nodig hebt

| Wat | Waarom | Kost |
|---|---|---|
| Mac met **macOS 15.6+** | Xcode 26, dus Liquid Glass | — |
| **Xcode 26+** (App Store) | Bouwen en installeren | Gratis |
| `brew install xcodegen node` | Project genereren en databasetests | Gratis |
| **Supabase-account** | Backend | Gratis plan |
| **Apple Developer Program** | TestFlight en de app op haar iPhone | ~€99 per jaar |

Met een gratis Apple ID kan je de app enkel op een toestel zetten dat met een kabel aan je Mac hangt. Ze stopt dan na 7 dagen met werken.

## 1. Repo en tools

```bash
git clone https://github.com/Graphic-lab/ChatApp.git && cd ChatApp
xcodebuild -downloadPlatform iOS      # simulator, eenmalig
buildkit/check-env.sh
```

## 2. Supabase-project

1. Ga naar supabase.com → **New project**. Kies regio **West EU** en bewaar het databasewachtwoord.
2. Open de **SQL Editor** en voer in deze volgorde uit:
   1. `supabase/migrations/0001_core.sql`
   2. `supabase/migrations/0002_storage_realtime.sql`
   3. `buildkit/owner-setup.sql`, **met jouw e-mailadres** en dat van je partner
3. Ga naar **Authentication → Sign In / Providers → Email**:
   - Email: aan
   - Confirm email: aan
4. Ga naar **Authentication → Emails → Magic Link**. Vervang het sjabloon door een code:
   ```html
   <h2>Je code voor Heart to Heart</h2>
   <p style="font-size:28px;letter-spacing:4px"><b>{{ .Token }}</b></p>
   ```
   Doe hetzelfde voor **Confirm signup**.
5. Ga naar **Project Settings → API**. Kopieer de **Project URL** en de **anon / publishable key**.
   - Gebruik **nooit** de `service_role`-sleutel in de app.
6. Zet **2FA** aan op je Supabase-account. Dat account is de echte master key (ADR-0005).

Supabase verstuurt standaard maar enkele e-mails per uur. Voor 2 personen volstaat dat. Voor meer gebruikers stel je eigen SMTP in.

## 3. App configureren

```bash
buildkit/bootstrap.sh
```

Vul daarna `ios/Config/Secrets.xcconfig` in. Het bestand is git-ignored.

```
SUPABASE_URL = https:/$()/abcdefgh.supabase.co
SUPABASE_ANON_KEY = eyJ...
DEVELOPMENT_TEAM = ABCDE12345
```

- Je **Team ID** vind je op developer.apple.com → Membership.
- Zet `$()` tussen de twee slashes. xcconfig ziet `//` anders als commentaar.

## 4. Verifiëren

```bash
buildkit/verify.sh
```

Dit draait de databaseregels (11 tests) en daarna de iOS-build met unit tests in de simulator.

## 5. Op je eigen iPhone

1. Open `ios/HeartToHeart.xcodeproj`.
2. Ga naar Target **HeartToHeart → Signing & Capabilities** en zet **Automatically manage signing** aan.
3. Sluit je iPhone aan. Zet **Ontwikkelaarsmodus** aan via Instellingen → Privacy en beveiliging.
4. Kies je iPhone als bestemming en druk op **⌘R**.
5. Log in met je e-mail. Je wordt automatisch owner.

**Test op een echt toestel:**
- De microfoon en spraakherkenning werken niet goed in de simulator.
- Apple Translation werkt alleen op een echt toestel. In de simulator verschijnt een foutmelding en zie je het origineel.

## 6. Op de iPhone van je partner (TestFlight)

1. Maak in App Store Connect een nieuwe app met dezelfde bundle-ID (`APP_BUNDLE_ID`).
2. In Xcode: **Product → Archive → Distribute App → TestFlight Internal Only**.
3. Ga in App Store Connect naar Users and Access. Voeg je partner toe als gebruiker met de rol Marketing of Developer.
4. Ga naar TestFlight → Internal Testing en voeg je partner toe.
5. Je partner installeert **TestFlight** uit de App Store, opent de uitnodiging en installeert Heart to Heart.
6. Je partner logt in met het e-mailadres dat je uitnodigde.

TestFlight-builds vervallen na 90 dagen. Upload dan een nieuwe build.

## 7. Eerste gebruik

Doe dit op beide toestellen:
1. Ga naar **Instellingen**:
   - naam
   - "Ik lees en hoor" (bv. Nederlands of Українська)
   - "Ik spreek meestal"
   - "Mijn stem bij de ander"
2. Ga naar **Contacten → +** en vul het e-mailadres van de ander in.
3. Ga naar **Chats → potlood → Nieuw gesprek**.
4. Houd de microfoon ingedrukt en spreek. Laat los om te versturen. Tikken kan ook: één tik start, een tweede tik stopt.
5. De eerste vertaling vraagt iOS om het taalpakket te downloaden. Kies **Download**.

## Problemen

| Symptoom | Oplossing |
|---|---|
| "Backend niet ingesteld" | `Secrets.xcconfig` is leeg of bevat placeholders. Draai daarna opnieuw `xcodegen generate`. |
| "Dit e-mailadres is nog niet uitgenodigd" | Voeg het adres toe via Instellingen → Beheer, of via `owner-setup.sql` |
| Je bent geen owner | Je logde in vóór `owner-setup.sql`. Los het op in de SQL Editor: `update profiles set role='owner' where email='…'` |
| E-mail bevat een link en geen code | Stap 2.4: pas het e-mailsjabloon aan |
| Vertaling mislukt | Download het taalpakket via Instellingen → Apps → Vertaal → Gedownloade talen |
