# Hot-wallet-server development checkpoint

Owner: WRAPPED ECX SOL, controller-registered extraction lane. Parent is the only
writer; review agents are read-only. New repository path:
`/Users/lukekensik/Documents/Codex/hot-wallet-server`, branch `main`.
Original bridge stays clean at `6af7e73818c041669c5a5c1819f4c5c0be405d37`.
Do not modify/deploy original runtime or touch live custody during extraction.

## Implemented and checked

- Wrapping-only cleanup: removed standalone mint/burn, metadata, nonce, pool,
  position/liquidity builders and unused token key/offline-signing operations.
  ATA setup retains its closed DSL, exact saved format, validation, locks and
  saved-before-send behavior. Token saved validators now live in Token.hs.
  Source count (tracked .hs/.rs/.c excluding src/test; Rust inline tests included):
  17,762 -> 16,903 lines, 66 -> 64 files. Administration: 873 -> 354 lines,
  5 -> 3 files. SDK: 792 -> 538 lines including its tests. Core financial paths
  and upstream checkout are unchanged. Build-all and full local bridge-test PASS;
  evidence and scoped independent verdict are in .audit/wrap-only.tsv and DONE.md.
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
   Opaleye DSL operations. Only the current schema is supported at the user’s request; schema changes
   require an explicit deployment decision. Never reset an existing ledger.
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
5. Real disposable PostgreSQL scheduling/setup/recovery contracts, full source
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

## Current-schema cleanup

Only schema 22 is supported. `src/schema.sql` replaces all historical SQL files;
Store.Migration and old-only fixtures are removed. Initialization lives in
Store.Provision; existing matching ledgers are preserved, old ones refused.
Current-schema backup/restore and payment invariants pass actual isolated PostgreSQL
contracts; all local build/test logs are in `.audit/current-schema.tsv`.
Config examples are deleted; example.conf remains. No live data changed.

## Library-owned severity existential

The bridge now pins operation-capabilities0.1.1.0 at
`d10f6168cddcb01e89517546dd5c4b8749829c3e` (published tag v0.1.1.0).
`Control.Operation.Severity` owns Safe/Critical and the opaque nominal
`SomeOperationAt program caller severity result`. Pending is removed; signer
handlers and evaluator boundaries use the library type directly. Plan only selects
safe/critical routing. The closed Program, eqT check, unique result families,
runtime authorization and single critical call site are retained.

Build-all, full bridge-test (220 property checks), positive capability compilation
and nine expected compiler rejections PASS. Library checks: eight properties with
10,000 cases each and 21 expected compiler rejections PASS; separate library review
passed before publication. Commands/hashes are in `.audit/severity.tsv`.
Internal.hs shrank235->228lines; the reusable library adds one41-line module.
No live custody, service or schema changed. The unrelated indexed-pipeline branch
remains untouched. Broader payout/installer/production gates above remain open.
Fresh separate `single_schema_audit` passed staged diff
`8549f4c757898b157e018420ed5079c3dd3dbac9c8acc974a6f43c309b27e5aa`;
only verdict metadata was appended afterward.

Follow-up: Operation.interpret now branches after Refl using combined Context
constraints. Execution methods receive Program directly; command/compileOperation,
the selector adapter and request reconstruction are gone. Both production files
lose14lines total; six test lines add combined-capability and lazy-mismatch coverage.
Build,221local property checks,nine compiler rejections and disposable PostgreSQL
canonical-profile server/HTTPS signer contracts PASS. All temporary test processes
are stopped. See DONE.md and the appended `.audit/severity.tsv` entries.
Fresh separate `current_schema_verifier` passed staged diff
`44cd5d5267df3100cd713b104f7b9e9fd2468a246719d2cbdc91feca34171891`;
only verdict metadata was appended afterward.

## Critical evaluator readability checkpoint

The readability-only evalCritical change has a separate source-equivalence PASS;
see DONE.md and .audit/severity.tsv. Full local suite: 223 checks; all five
disposable PostgreSQL/process modes pass on the combined working tree.
Payout-round work remains unstaged, including schema 23 and configuration wiring.
Before publishing it, resolve admission-capacity saturation: funded tiny orders
below the aggregate threshold can fill maximumQueued and prevent progress. Do not
waive the configured threshold or treat a larger finite cap as a complete fix.
Update current schema documentation and obtain a fresh final review afterward.
No live ledger, custody or deployment changed; production gates remain FAIL.

Installation URL validation is independently reviewed and tested; see DONE.md and
.audit/layout.tsv. Unpublished payout work still fails liveness review for pending
quote/round timing, shared fees and extreme thresholds. User policy choice is
pending; do not treat its passing fixture suite as release acceptance.

Installer source staging now has Ubuntu 24.04 arm64 execution evidence for the
production extraction/locking blocks (see DONE.md and .audit/layout.tsv), following
the published GHC JS discovery correction. Task-only test VM/container removed;
all preexisting Colima profiles still stopped. No compiler or node started.
Next installer work: validate original configuration permissions before copying,
then complete whole-host unattended install/repeat/reboot acceptance. Source-stage
checks do not certify the toolchain bootstrap, service provisioning or production.
Payout-policy choice remains pending and failed payout work remains unpublished.

Security setup: Codex Security was confirmed available/not installed and its app
installation was requested. No current standalone scan is running; prior upstream
receipts are not acceptance. Fresh cargo-audit found zero matched vulnerabilities
among148 dependencies, retaining bincode maintenance warning; details/hashes in
DEPENDENCY-REVIEW.md and .audit/layout.tsv. Await plugin installation confirmation,
then run whole-source review on the actual candidate including any completed
payout changes. Keep Cabal/base reachability findings and production gate open.

Original configuration permissions and atomic-copy checks are now implemented and
verified in Ubuntu; prior next-step item is complete only for this scope. See
DONE.md/.audit/layout.tsv. Next: complete whole-host installer/toolchain/service
acceptance, while payout-policy choice and Codex Security installation are pending.
No task VM/container remains. Public activation and financial release stay blocked.

## Reviewed backup-tool provisioning (2026-10-10)

PASS for this scope: install.sh builds restic without root or custody credentials,
verifies the unchanged source/patch/binary pins, and publishes verified bytes in a
root-owned directory. Existing different binaries are refused; matching retries
preserve the installed file. Both ARM64 and x86-64 builds reproduce the exact
pinned checksums. The build recipe uses Go1.26.9 without stripping debug symbols.
Ubuntu24.04 x86-64 checks passed actual execution, root0755 publication, unchanged
retry, altered-byte/permission refusal and symlink refusal. See .audit/layout.tsv.
This is dependency build/publication acceptance, not a full fresh-host installation
or independent security approval. Financial and public-release gates remain open.

## Owner public-key validation (2026-10-10)

PASS: record setup validates the owner's mainnet BIP32 public key structure,
checksum, root metadata and compressed secp256k1 curve point before writing setup.
The existing libsecp256k1 dependency performs point parsing; no signing path or
new dependency is added. Eight malformed-key cases, including recomputed-checksum
semantic failures, pass the real configure-file refusal contract; valid-key replay
still passes. Fresh read-only single_schema_callgraph scoped review PASS.
This validates key encoding, not owner possession or automatic earned-fee sweeps;
those sweeps and broader production gates remain incomplete. Specification:
https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#serialization-format

Configured customer links are now wired through record setup, interface.json and
the browser (see DONE.md and .audit/layout.tsv). Owner withdrawals still require
paused operator authorization; automatic sweeps must use a distinct closed ledger
authorization and the resolved payout-round policy, not bypass that check.

## Security review follow-up

Codex Security remains not installed; no plugin scan was run. A separate read-only
review of HEAD1ae0700 found that an absent saved attempt wrongly permitted
cancellation of a potentially signed draft. The protective fix refuses complete
drafts in Store and lifecycle decisions. Do not represent this as full recovery
completion: safe complete-draft cancellation and audit of any historical completed
cancellations remain release work. Public access remains off. The abstract signer
gate model now explicitly checks mutual exclusion with three failing mutations.

Separate review also confirmed native RPC server impersonation risk: managed node
uses ordinary loopback HTTP on unprivileged port 28532 with persistent Basic RPC
credentials. A different local UID can bind the port during node downtime. Chain
identity replies are not server authentication. Resolve with authenticated node
transport or an enforced OS binding/network boundary, and test restart/takeover
refusal before production. No live endpoint or credentials were exercised.

### Managed native RPC guard checkpoint

Implemented managed loopback socket-UID enforcement, packaged helper, systemd
dependencies and early endpoint validation. Disposable Ubuntu socket, lifecycle,
cold-boot and re-enable refusal checks passed; isolated configure-only suite passed.
See .audit/layout.tsv for exact evidence. No live wallet/service/funds touched.
Next: real-node/full-install acceptance and remaining cancellation/release gates;
keep public access off. This does not resolve external node transport or arbitrary
privileged firewall changes. Unrelated payout/schema work remains unpublished.

### Cancellation verification follow-up

Historical successor admission now checks raw nullable draft_json for every
cancelled generation. Pure suite and real disposable PostgreSQL contracts passed,
including complete-native-resume isolation and backup/restore. No schema changes.
The complete-draft cancellation restriction remains: no assertion that missing
recorded bytes means unsigned. Historical already-created successors/reserve
releases still require audit/quarantine before production. Payout WIP remains
unpublished; public activation remains off.

### Historical quarantine checkpoint

Cancelled populated drafts now quarantine spending deployment-wide, including
previously admitted successors. Local PostgreSQL historical-successor and ordinary
contracts passed on the isolated schema22 candidate; mixed schema23/payout WIP is
excluded. Read-only cancellation_release_verifier source/test verdict: scoped PASS.
Native executable compilation passed; the pure suite was not rerun this turn.
The disposable PostgreSQL cluster is removed; no live services/funds changed.

Next: audit actual funded-ledger history and resolve remaining recovery/release
gates. AWS ecx-dev authentication expired; the attempted login also timed out
without user sign-in. No current EC2 state or remote ledger has been verified.
No AWS login process remains. Public access stays off.
