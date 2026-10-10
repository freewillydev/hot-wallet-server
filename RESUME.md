# Hot-wallet-server development checkpoint

Owner: WRAPPED ECX SOL, controller-registered extraction lane. Parent is the only
writer; review agents are read-only. New repository path:
`/Users/lukekensik/Documents/Codex/hot-wallet-server`, branch `main`.
Original bridge stays clean at `6af7e73818c041669c5a5c1819f4c5c0be405d37`.
Do not modify/deploy original runtime or touch live custody during extraction.

## Implemented and checked

- Server subtree extracted into `src/`, documentation into root `docs/`; root Cabal
  project/freeze retained. Source/runtime packaging paths adjusted for new layout.
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
  `.audit/wallet-mode-receipt.json`. Fresh `wallet_mode_verifier` scoped PASS.
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
Reuse the already built browser and FFI assets for local server-only edits:

```
ECX_BROWSER_PREBUILT=/tmp/ecx-path-log-build/build/aarch64-osx/ghc-9.14.1/ecx-build-assets-0.1.0.0/build/autogen/web
CARGO_TARGET_DIR=/tmp/ecx-path-log-build/build/aarch64-osx/ghc-9.14.1/ecx-build-assets-0.1.0.0/build/autogen/cargo
```

Set those for the Cabal commands in AGENTS.md. Targeted test log:
`/tmp/hot-wallet-wallet-mode-test.log`. Full extracted `bridge-test` suite also PASS, session69904 exit0, log
`/tmp/hot-wallet-server-full-test.log`. No owned long-running processes remain.
Neither test invokes the disposable PostgreSQL financial matrix or a real install.

Private GitHub development checkpoint publication is authorized and being reviewed
by `server_extraction_review`. It is not a declaration of installation completion.
After push, record exact commit, remote equality/private visibility and reviewer
receipt in .audit/extraction.tsv. Never include real server.conf, credentials,
wallets, database state, build caches or live key material.
