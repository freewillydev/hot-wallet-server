# Bridge development

Read Docs/IMPLEMENTATION-PLAN.md before architecture work. The current priority is
human-auditable simplification: remove duplication, obsolete artifacts and unnecessary
abstractions while preserving required behavior and financial invariants.

Before operation, handler or interpreter changes, read Docs/reference/Main.hs in full
and Docs/ARCHITECTURE.md. Main.hs is the user's exact architectural reference from
“Add interactive environment prompts”, supplied 2026-10-02. Keep it unmodified and
outside production builds. Preserve the typeclass/constrained-existential/GADT
severity design; correct the sketch's incomplete or permissive types as explained
in the DSL guide. Keep separate safe/critical evaluators and one authorized critical
dispatch site. Re-read the reference after context loss when doing architecture work.

Use targeted reads, one build job, and no idle task VMs. Consolidate tests and
documentation instead of creating a new report or executable for each small change.
Keep required licenses and dependency locks.

Database access: use Opaleye for all application reads/writes, diagnostics, role
checks and database test fixtures/assertions. No raw SQL query/execute escape path
for those operations and no alternative database backend. Underlying libpq
connections/transaction control and schema-migration DDL are separate infrastructure.

Opaleye queries belong only to implementations of specific closed DSL operations.
Do not expose connection/query callbacks or generic RunQuery/RunSQL operations to
handlers. Keep connection capabilities private to the relevant interpreter.

Run Cabal build/test commands from the root (one build job). Use Cabal hooks for
non-Haskell compiler inputs; do not require separate application build commands.
Keep customer HTTP limited to configuration/order/payment instructions. Local
operator control must use the closed DSL dispatcher, not operator HTTP routes.
SQLite and its legacy test library are retired; use QuickCheck and actual
PostgreSQL contracts. Run bridge commands from the repository root. The standalone token and pool CLIs
remain in the upstream ecx-solana-bridge repository; they are not included here.


## How to run and verify this project

From this repository root, use GHC 9.14.1 and Cabal 3.16.1.0. Build prerequisites
and GHC JavaScript/Solana FFI setup are in Docs/LOCAL-DEVELOPMENT.md. One job only:

- Build: `cabal --project-dir=build build exe:ecx-bridge -w ghc-9.14.1 -j1`.
- Test: `cabal --project-dir=build test bridge-test -w ghc-9.14.1 -j1 --test-show-details=direct`.
- Focused wallet setup: append `--test-options=--configure-only` to that test command.
  It uses disposable fixture keys, real executable imports and terminal-driven
  startup preparation; it does not contact a chain or provision services.
- Installer syntax: `sh -n build/install.sh build/install/toolchain build/install/source`.
- Actual deployment: only `sudo ./build/install.sh /absolute/private/server.conf` on an
  isolated Ubuntu 24.04 host after outstanding installer/config gates are resolved.
  A local build does not prove clean-install or funded acceptance.
- Durable payout-round checks require the real disposable PostgreSQL contract;
  this feature is pending. Never substitute fixture success for financial acceptance.
- Layout/provenance: compare src/ to upstream server commit 6af7e73818c041669c5a5c1819f4c5c0be405d37,
  inspect staged files for private inputs, and confirm the original checkout is unchanged.
- Publication: verify GitHub privacy and remote HEAD against the separately reviewed
  commit. Record that verifier's exact scope and PASS/FAIL in Docs/DONE.md and Docs/.audit/.

Wallet generation is restricted to interactive startup. Record-based setup must
validate and preserve supplied ECX/Solana keys; never add missing-key generation
fallbacks. Test mixed-mode and interrupted-import refusal when changing this flow.
Docs/DONE.md is the authoritative acceptance checklist; pending checks stay FAIL.
