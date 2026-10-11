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

## Wrapping-only source cleanup (2026-10-10)

PASS: pinned Cabal `build all` and full `bridge-test`, one job, native cache
`/tmp/hot-wallet-server-build`. The suite includes locked/offline SDK codec/FFI
contracts, exact ATA setup/record replay, retired-operation rejection, status
consistency, signing transport, recovery, lifecycle, customer routes and website.
The rebuilt SDK exports only `ecx_solana_prepare_v1` and `ecx_associated_prepare_v1`.
The original upstream checkout is still clean at `6af7e73`.

Removed token mint/burn, metadata, nonce and liquidity-pool builders, unused key/
offline-signing operations, their uncalled replacement writer, two modules and two
direct Rust dependencies. Existing ATA signature/lineage validation and protected
saved-before-send submission remain. No customer financial operation was removed.
Application/SDK source files: 17,762 -> 16,903 lines; 66 -> 64 files (tracked Haskell,
Rust and C excluding src/test; Rust inline tests included). Separate Haskell tests:
10,246 -> 10,224 lines, with focused tests replacing obsolete-feature tests.

Independent `/root/wrap_only_verifier`: **PASS** for source/build diff SHA256
`39a9b3924d48276c3ab3b396caed6183603298c76ce1a24258effffd6af212da`
against baseline `ec068ad`. No blocking findings. Log hashes are in
`.audit/wrap-only.tsv`.
No new funded, PostgreSQL, Ubuntu installation or overall production acceptance
is claimed; all broader open gates above remain PENDING/FAIL.

## Current schema only (2026-10-10)

PASS: one `src/schema.sql` replaces ten migration files (1,008 -> 756 lines).
Historical schema projections and conversion operations are removed. Provisioning
and initialization are one module (495 -> 187 lines); unsupported backup schemas
are rejected before archive access or database creation. Current restore preserves
exact attempts and financial records and stays paused. The four optional config
examples (78 lines) are removed; `example.conf` is the only operator example.

Actual PostgreSQL schema-only dumps match exactly. Build-all, full bridge-test,
provisioning rollback/SIGKILL/retry and isolated current-schema restore, the default
financial contract, fresh initialization and residual-history refusal all PASS.
The temporary databases/processes were stopped and removed. No live funds moved.
Evidence: `.audit/current-schema.tsv`. Independent `current_schema_verifier` PASS
for staged diff SHA256 `07fcc04827636d27f34f97f02cd2006a2cdf0a62dd07e74063e7447e667769c2`;
only this verdict metadata was added afterward. Overall production/payout/Ubuntu
installation gates remain FAIL. Old migration-based
bundles and changed schema hashes refuse automatic upgrade.

## Library-owned severity existential (2026-10-10)

PASS: build-all and the full local bridge-test suite against library0.1.1.0 at
`d10f6168cddcb01e89517546dd5c4b8749829c3e`. The bridge's Pending wrapper is removed;
the library's opaque nominal SomeOperationAt carries program/caller/severity/result.
The original closed grammar, eqT proof, unique signer outputs, runtime checks and
sole critical dispatch call remain. Existing HTTP dispatch/transport checks pass.
One positive and nine negative compilation checks passed with the expected
capability/type diagnostics. Library tests independently passed80,000 cases and
21 compiler rejection checks; separate library review passed before publication.
Evidence: `.audit/severity.tsv`. No new funded, PostgreSQL or Ubuntu acceptance
is claimed; broader production gates remain FAIL.
Independent `single_schema_audit`: scoped PASS for staged diff SHA256
`8549f4c757898b157e018420ed5079c3dd3dbac9c8acc974a6f43c309b27e5aa`;
only this verdict metadata was appended afterward.

## Branching after payload equality (2026-10-10)

PASS: `interpret` branches over all six commands only after `Refl`; its Context
combines compilation and execution evidence. Execution methods consume the compiled
Program directly. The command/compileOperation forwarders, selector adapter and
Program-to-Command reconstruction are removed. Production source: Internal.hs
228->226lines, Critical.hs1,019->1,007lines (14 fewer; no file added).
Build-all and221local property checks pass, including rejection without forcing
a mismatched payload. Combined-capability compilation and nine intended rejections
pass. Disposable PostgreSQL canonical-profile server/TLS contracts pass with real
HTTPS and fixture signing: authorization/rotation, serialization, changed-decision
refusal, durable replay and checkpoint behavior. No live network/funds were used.
Evidence is appended to `.audit/severity.tsv`; production gates remain FAIL.
Fresh separate `current_schema_verifier`: scoped PASS for staged diff SHA256
`44cd5d5267df3100cd713b104f7b9e9fd2468a246719d2cbdc91feca34171891`;
only this verdict metadata was appended afterward.

## Critical evaluator readability (2026-10-10)

Scoped PASS: evalCritical now separates authorization, signer dispatch and the four
operations visibly, with named RPC aliases and SignedAttempt fields. The function
is 67 -> 115 physical lines (+48, mostly layout); no new file or authority path.
The sole call, gate, checks, IO ordering, cleanup and unique results are unchanged.
Independent single_schema_callgraph passed source diff SHA256
`e811cdace6a4a0e0c82a8d5f0254dbc929ec0baee1db8db626e069897c56d2f0`.
Build, 223 local checks and five disposable PostgreSQL/process modes pass on the
combined working tree, which also contains unstaged payout work. Only this
readability refactor is published here; this is not a production acceptance claim.
Evidence: `.audit/severity.tsv`. Temporary test services stopped; no funds moved.

## Installation URL validation (2026-10-10)

Scoped PASS: record setup validates printable-ASCII HTTPS URLs and backup URI
structure before private publication, rejects backup fragments and redacts parser
exceptions. Six malformed backup inputs join real configure-file refusal/replay
checks. The targeted configure contract PASSes; no chain or services were used.
Separate single_schema_callgraph PASS for source diff SHA256
`d7605419c9d508443d53404892225b3d9077a52f5afb137ee729f5b71294ecbe`.
Evidence: `.audit/layout.tsv`. Payout and production gates remain open.

## Installer compiler discovery (2026-10-10)

PASS for the scoped GHC JavaScript discovery correction: use the pinned installed
compiler directory reported by GHCup, and require its matching executable package
tool before building. Shell syntax and isolated shell checks cover spaces in paths,
failed lookup, missing compiler and non-executable package tool. Separate read-only
single_schema_callgraph review PASS; see .audit/layout.tsv. No Ubuntu installation
or production acceptance is implied. No live service or custody was changed.

## Installer source publication (2026-10-10)

The installer captures one Git commit, checks archive creation before extraction,
then extracts as the build account into a temporary directory and atomically
publishes a commit-specific source tree. Same-commit retries retain caches;
new commits cannot inherit deleted source files. A private flock serializes installs.
Ubuntu 24.04 arm64 checks PASS for fresh/repeat extraction, build-user ownership,
new-commit isolation, mismatched identity, archive failure, malformed archive,
source symlink refusal and concurrent-install exclusion. The harness exercises
production script blocks with real Git/tar/runuser/flock; this is not a complete
Ubuntu build/install/reboot acceptance. Logs and hashes are in .audit/layout.tsv.
The temporary 1GB VM and its container were stopped and deleted; other profiles
remain stopped. No live deployment or custody changed.

Fresh separate single_schema_callgraph review: **PASS** for the exact installer
hash, test harness and final execution log above; broader gates remain open.

## Standalone dependency refresh (2026-10-10)

Fresh cargo-audit checks 148 dependencies against 1,296 RustSec advisories: no
matched vulnerability advisories, unmaintained bincode still flagged. Current FFI
and record-config boundaries are described in DEPENDENCY-REVIEW.md. This does not
waive bincode, Cabal or base findings, certify transitive reachability, or close
the independent security gate. Codex Security is available but not installed;
installation has been requested through the app and no new scan was run.

Fresh separate single_schema_callgraph review PASS for the refreshed report,
source boundaries, frozen versions and advisory status; security gate remains open.

## Private installation configuration (2026-10-10)

PASS: original file/directory and saved-state permissions, bounded same-descriptor
copy, atomic publication, unchanged retry and failed-copy recovery in Ubuntu24.04.
Fresh separate single_schema_callgraph verified final source/harness/log hashes;
see .audit/layout.tsv. +28 production lines, no new production files. Task-only VM
and container deleted. These prefix checks do not certify full installation,
power-loss durability or any financial/public-release gate.

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
