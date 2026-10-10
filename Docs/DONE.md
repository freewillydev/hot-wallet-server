Done means: hot-wallet-server repository with requested layout, typed record configuration, unattended install.sh, durable configurable customer payout rounds, accurate README and verified standalone checks plus independent PASS.

All below currently PENDING/FAIL until evidence exists; do not mark finished early.
- Scope/layout/provenance: server-only src/Docs/build, no token/pool executable, originalunchanged.
- Config: bounded Read/Eq typedrecord, noShowsecrets/noeval, completevalidation, replaybinding.
- Installer: noTTY/prompts, externalinputsmodularstrings, repeat-safe, Ubuntu sourcebootstrap.
- Payouts: perassetnetthreshold+configurablehours, allreadyroundsnapshot, durablereplay,
  noquoterepricing/noeffect onsettlement orsignedattemptrecovery, customersseepolicy.
- Tests: Cabal + realdisposablePGroundcontracts + scriptsyntax + nosecretfiles.
- Review: separatefreshread-only verifier scopedPASS.
- GitHub: PUBLIC freewillydev/hot-wallet-server main matches final reviewed commit.
  Public source visibility was explicitly confirmed by the user on 2026-10-10;
  this does not authorize public activation of an unfinished live server.

This extraction does not certify production; existing security/manualwallet/alerts/
release-trust/public-access gates remain open. No live deployment is authorized by
this scoped work and no livecustodychanged.

## Scoped wallet-mode check (2026-10-10)

PASS: `cabal test bridge-test -j1 --builddir=/tmp/hot-wallet-server-build --test-show-details=direct --test-options=--configure-only`
finished with exit0 (session44193). Exact source and log hashes are recorded in
`.audit/wallet-mode-receipt.json`. It verifies supplied identity preservation,
invalid/missing/Unicode input refusal, immutable retry, interactive-start-only
wallet generation, mixed-mode refusal, and backup timeout child cleanup.

Fresh separate `wallet_mode_verifier`: **PASS for that scope** after reviewing all
8 source hashes and the matching execution log. The broader checklist above
remains PENDING/FAIL. In particular: Ubuntu install, durable payout policy,
Cloudflare/owner wiring, PostgreSQL schedule/recovery and production are not certified.

Full extracted `bridge-test` suite also PASS (session69904 exit0,
`/tmp/hot-wallet-server-full-test.log`). This is the local suite; the separate
PostgreSQL financial contracts and Linux installation remain unrun here.

## Private source checkpoint publication

PASS for source-only publication: independent `server_extraction_review` bound
staged tree `9c2778f88db423b1b17fd4f096a7ced87f4840a6`; committed as
`10e36ae6def507bb7ecb6ed04d992668f0c84f68`. GitHub
`freewillydev/hot-wallet-server` is PRIVATE and its main branch matched that commit
at publication. This does not mark the broader finish line complete.

README simplification: scoped PASS by `/root/readme_simplify_review`, bound to
SHA256 `a2b0ccbbcdba19faa703046487a87ad0c2316a343aaf4d8203e209958cc3f28a`. Configuration syntax,
all six links and the single install command checked against source. No readiness
gate changed and no new runtime acceptance is claimed.

## Repository layout (2026-10-10)

Scope: agent documentation and records under `Docs/`; Cabal, SDK/browser build
metadata and installer support under `build/`; application source under `src/`.
README links the moved agent instructions/checklist/resume; installation starts
with `sudo ./build/install.sh /absolute/private/server.conf`.

PASS: native executable and `bridge-test` built with `cabal --project-dir=build`;
GHC JavaScript browser recompiled, SDK and local tests passed (session97911 exit0,
`/tmp/hot-wallet-layout-test.log`). Shell/Python syntax, nine README links, exact
path case, unchanged architectural reference and rebuilt browser manifest passed.
A fresh Git archive resolves all Cabal targets with the pinned dependency (dry-run,
session80273 exit0; `/tmp/hot-wallet-layout-archive-plan.log`). No standalone
`cabal sdist` support is claimed; builds use the complete checkout/archive.
Independent `/root/layout_final_verifier`: PASS for staged tree `12fa156b1dc0242b982eb86ed37ff3c11e978e10`.
No blocking findings. This verdict covers the layout only; all broader installer,
payout, PostgreSQL and production checks above remain PENDING/FAIL.

## Custom frontend (2026-10-10)

Scope: optional `websiteDirectory` record input, three fixed public files,
immutable setup hashes, protected installed copy retained across upgrades, and
bounded startup snapshots. Same customer API, CSP and evaluator boundaries.
Build PASS (`/tmp/hot-wallet-website-build.log`, session1786 exit0); installer shell
syntax and `git diff --check` PASS. Full local `bridge-test` PASS
(`/tmp/hot-wallet-website-test-final.log`, session3902 exit0), including file
protection, API routing, immutable snapshot and real configure-file replay checks.
Independent `/root/website_final_verifier` PASS for staged tree
`b8091c3fb943b134642664e8c519f9c55295e42a`; no blocking findings.
Ubuntu custom-site install/reboot/upgrade acceptance remains unrun; this
feature does not close the broader installer or production gates.

README permissions/custom-site instructions: independent `readme_permissions_verifier`
PASS for SHA256 `c4be49c2d98ee1a626a533bbc2eaf3ee17376dfaaac65e7b6af1cd2b6e7bf0d1`.
Shell syntax and all ten links verified; documentation only, no deployment claim.
