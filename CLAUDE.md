# ChatApp — Heart to Heart

Operating contract for all AI-assisted work in this workspace:

@_prompt/Prompti-Repo-Orchestration-v32.md

## Layout

- `specs/` — source of truth: requirements (IDs R-*), design, tasks (T-*), ADRs. Update specs with any behaviour change.
- `ios/` — native SwiftUI app, generated with XcodeGen from `ios/project.yml`. Never commit `HeartToHeart.xcodeproj` or `Config/Secrets.xcconfig`.
- `supabase/migrations/` — schema and all authorization rules. New changes go in a new numbered file; never edit an applied migration.
- `supabase/tests/` — PGlite tests that execute the real migration.
- `buildkit/` — setup and verification scripts.
- `heart-to-heart-ukrainian-dutch/` — Lovable web POC, separate git repo, git-ignored here. Its own rules apply:

@heart-to-heart-ukrainian-dutch/AGENTS.md

## Non-negotiables

- Owner protection (R-OWN-*) is enforced in Postgres. Never move it to client-only checks or weaken triggers/RLS.
- No secrets or real e-mail addresses in the repo (it is public).
- Do not push to the POC repo without asking: every push syncs back to Lovable.

## Verification gates

1. `cd supabase/tests && npm test` — database rules
2. `buildkit/verify.sh` — database rules + iOS build and unit tests (needs an iOS simulator)
3. Physical iPhone for microphone, speech recognition, Apple Translation and AirPods (not testable in simulator)

## Notes

- Provenance workflow `/gap` from the contract does not exist yet (UNKNOWN until set up).
- Liquid Glass code is behind `#if compiler(>=6.2)`; it only compiles with Xcode 26+. Verify it there.
