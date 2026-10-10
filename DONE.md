Done means: private hot-wallet-server repository with requested layout, typed record configuration, unattended install.sh, durable configurable customer payout rounds, accurate README and verified standalone checks plus independent PASS.

All below currently PENDING/FAIL until evidence exists; do not mark finished early.
- Scope/layout/provenance: serveronly src/docs, no token/pool executable, originalunchanged.
- Config: bounded Read/Eq typedrecord, noShowsecrets/noeval, completevalidation, replaybinding.
- Installer: noTTY/prompts, externalinputsmodularstrings, repeat-safe, Ubuntu sourcebootstrap.
- Payouts: perassetnetthreshold+configurablehours, allreadyroundsnapshot, durablereplay,
  noquoterepricing/noeffect onsettlement orsignedattemptrecovery, customersseepolicy.
- Tests: Cabal + realdisposablePGroundcontracts + scriptsyntax + nosecretfiles.
- Review: separatefreshread-only verifier scopedPASS.
- GitHub: private freewillydev/hot-wallet-server main matches finalreviewedcommit.

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
