# Hot-wallet-server development checkpoint

Owner: WRAPPED ECX SOL, controller-registered extraction lane. Parent is the only
writer; review agents are read-only. New repository path:
`/Users/lukekensik/Documents/Codex/hot-wallet-server`, branch `main`.
Original bridge stays clean at `6af7e73818c041669c5a5c1819f4c5c0be405d37`.
Do not modify/deploy original runtime or touch live custody during extraction.

## Implemented and checked

- Server source is in `src/`; documentation and agent records are in `Docs/`.
  Cabal metadata, asset hooks and installation support are in `build/`.
  Run from the root with `cabal --project-dir=build`; install via `build/install.sh`.
- Haskell `Read` configuration record and `configure-file` importer. Record contains
  no Show instance; private immutable files bind retries. Supplied ECX BIP-39 phrase
  and 64-byte base58 Solana keypair are mandatory and validated before publication.
- Latest user request: no wallet generation for record input. `configure` saves
  settings only; interactive `start` generates new custody. Advanced configure
  imports/restores; `start --advanced` enables generation. Partial record setup
  cannot become interactive generation, and mixed modes are rejected.
- Named executable/terminal regression checks cover exact imported bytes, omitted,
  empty, invalid and Unicode key input, retry identity, private permissions,
  changed-record refusal, no configure-time generation and interrupted startup.
- A demonstrated existing backup timeout race is fixed: SIGKILL is followed by
  waitForProcess so the child is reaped before returning the failure.
- Targeted Cabal configure contract PASS, session44193 exit0. Source/log hashes:
  `Docs/.audit/wallet-mode-receipt.json`. Fresh `wallet_mode_verifier` scoped PASS.
  This is source plus local execution evidence, not Ubuntu/production acceptance.
- README now documents real state; AGENTS contains verification commands. Draft
  unattended install.sh/toolchain scripts pass shell syntax only.

## Next work, in order

1. Implement durable customer payout rounds before claiming the installer ready.
   User requires both thresholds (default0.001 each), configurable interval
   `minimumPayoutIntervalHours` (default48), and ALL eligible customers per round.
   Persist exact per-asset membership and admission time; new arrivals wait for
   next round. Use immutable net obligations, keep retries admitted, preserve
   active-per-chain ordering. Gate preparation and signer decision independently;
   never delay observation, settlement or signed-attempt recovery. Use only closed
   Opaleye DSL operations. Schema22 needs an explicit versioned migration and
   pending-work backfill/verified backup; never reset an existing ledger.
2. Wire record policy through Config/StorePolicy and public timing presentation.
   Currently payout, Cloudflare and owner fields are only validated, NOT applied.
   Do not leave silently ignored configuration in a finished installer. Owner
   fee handling and customer timing must reflect the user's final requirements.
3. Finish unattended Ubuntu source installation: verify cross-compiler/toolchain
   paths, source archive replay/identity, reviewed restic provisioning and Cloudflare
   modular credentials. Only install.sh is the human entry point; external human
   prerequisites must return independent input strings. No public activation while
   production review gates fail. Supplied keys must never be replaced/generated.
4. Complete configuration validation (backup URLs, meaningful owner xpub), tests
   and fresh Ubuntu install/repeat/reboot acceptance. Keep one build job, no idle
   VMs. Linux installation has NOT been run for this new repository.
5. Real disposable PostgreSQL scheduling/migration/recovery contracts, full source
   checks, independent final extraction/install verdict and only then completion.
   Production security/manual-wallet/alerts/release-trust/public-access gates
   remain separate and FAIL; no inherited receipt certifies new changes.

## Build and evidence

GHC9.14.1 / Cabal3.16.1.0; build directory `/tmp/hot-wallet-server-build`.
The layout change rebuilt the browser with GHC JavaScript and passed the full
local suite (session97911 exit0), log `/tmp/hot-wallet-layout-test.log`:

```sh
env -u ECX_BROWSER_PREBUILT \
  CARGO_TARGET_DIR=/tmp/ecx-path-log-build/build/aarch64-osx/ghc-9.14.1/ecx-build-assets-0.1.0.0/build/autogen/cargo \
  ECX_BROWSER_BUILD_DIR=/tmp/hot-wallet-server-browser-build \
  cabal --project-dir=build test bridge-test -j1 \
    --builddir=/tmp/hot-wallet-server-build --test-show-details=direct
```

Do not reuse browser bundles from before the layout change: their source manifest
paths differ. New bundles are under the build cache's ecx-build-assets autogen/web.
The previous wallet-mode and full-suite receipts remain historical evidence.
No owned long-running processes remain. These local tests do not invoke the
separate PostgreSQL financial matrix or install Ubuntu services.

Private development checkpoint published:
https://github.com/freewillydev/hot-wallet-server (visibility PRIVATE verified).
Initial source commit `10e36ae6def507bb7ecb6ed04d992668f0c84f68` matches remote main;
its exact tree `9c2778f88db423b1b17fd4f096a7ced87f4840a6` received independent
`server_extraction_review` PASS for unfinished source checkpoint publication only.
All installer, payout and production gates remain pending. Publication evidence
is recorded in Docs/.audit/extraction.tsv. Follow-up protocol-only commits do not change
that reviewed implementation. Next implementation work is item1 above.

## Latest documentation change

README simplified from509 to249words (77 to42lines) at the user's request.
It retains Haskell-record configuration instructions, import-only keys, one
install command and the incomplete/public-off status. Independent read-only
`/root/readme_simplify_review` PASS for SHA256
`a2b0ccbbcdba19faa703046487a87ad0c2316a343aaf4d8203e209958cc3f28a`. Six links and git diff --check verified; no build required for
this documentation-only edit. Next implementation work remains payout rounds.

## Current layout checkpoint

Agent instructions/checklist/history now live entirely in `Docs/`, including
`Docs/.audit/`. Cabal/install support is in `build/`; root README is the discovery
entry point. The direct user request supersedes former root placement, without
removing a gate or history. Controller protocol is currently suspended; do not
message the coordinator. The original bridge checkout remains untouched.

Local native/browser compilation and local suite pass; fresh Git archive resolves
all Cabal targets. See Docs/DONE.md and Docs/.audit/layout.tsv for scoped evidence.
No installation or live-chain operation was performed. Repository is now PUBLIC,
explicitly confirmed by the user on 2026-10-10. Public server activation stays OFF.
Independent `/root/layout_final_verifier` passed staged tree `12fa156b1dc0242b982eb86ed37ff3c11e978e10`.
Only this verdict record was appended afterward. The layout change is ready for
publication; next implementation work remains the durable payout-round plan above.

## Custom frontend checkpoint

The new optional websiteDirectory field selects index.html, style.css and
dist/wallet.js (served as /, /style.css, /wallet.js). Configure binds file hashes;
installer verifies and copies them into /etc/ecx-bridge/worker/website, retaining
them across code upgrades via the worker ECX_ASSETS override. Web preloads bounded
regular files and rejects links/unsafe modes. No dependencies/processes/HTTP APIs
were added. CSP and financial operations are unchanged. Existing bound setup
records stay immutable; the new field must be present in new InstallConfig input.

Build/shell syntax and full local bridge-test pass (session3902 exit0,
/tmp/hot-wallet-website-test-final.log). Independent website_final_verifier PASS
for staged tree b8091c3fb943b134642664e8c519f9c55295e42a. Only verdict metadata
was appended afterward.
No custom-site Ubuntu deployment or live operation was performed. After this
scoped feature, the next substantive task remains durable payout rounds above.
