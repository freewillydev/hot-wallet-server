# Production acceptance

**NOT READY.** This checklist supersedes the chronological status notes below.
Application checkpoint: `240b974`; local acceptance recorded through `a80b7c5`.
Public source publication is authorized; public service activation remains gated.

Configuration-based updater: focused Cabal checks and separate static review PASS
(see `.audit/installer-update.tsv`). `update.sh` takes no arguments; live upgrade
acceptance is still pending. Older binaries need the documented bootstrap route.

2026-10-23 scoped config diagnostics PASS: application/test rebuilds and complete
local ConfigureCheck, including reordered/commented records and secret-safe
malformed-input errors through the real executable. Separate read-only
`config_record_review` source/evidence PASS. Original record bytes and custody
checks preserved. Validation used the committed Operation overlay because of
the unrelated dirty capability draft; no full dirty-tree Cabal, Ubuntu updater,
user-record diagnosis or live-deployment acceptance is claimed. Evidence hashes
are in `.audit/installer-update.tsv`; production gates below remain unchanged.

2026-10-23 self owner destinations: scoped build/configuration and actual local
PostgreSQL worker/signer contract PASS. Self fees remain Earned with no payment
root, balance change or attempt; external owner payout still reserves correctly.
Customer/manual safeguards unchanged. Fresh read-only `self_owner_review`
source/evidence verdict PASS. Net +4 production lines across four files.
Private test cluster stopped. Committed Operation overlay used as above; chain
RPC is fixture data, not real-fund or Ubuntu deployment acceptance.

Implemented: server-only layout, typed record setup, current schema23, customer
wrap/unwrap API, dedicated signer, configurable customer payout rounds, immediate
refunds, owner scheduling, custom frontend and optional tunnel setup. Local checks
prove their stated scopes, not production acceptance. Do not reimplement them to
resolve older "unimplemented" notes below.

| Release requirement | Current evidence | Still required / dependency |
| --- | --- | --- |
| Local build and financial regression | PASS: full Cabal suite9216 and rebuilt default PostgreSQL/process/restic contract45304 on current application; prior payout/TLS modes recorded in RESUME | Rerun affected checks only after relevant changes; fixture RPC is not real-network proof. |
| Native history and recovery | Projection fix has separate static PASS; 10,001-entry custody fixture556ms; actual daemon conflict capture tested earlier | Integrated current scanner/ledger recovery and sustained real-network load. Requires suitable synchronized node/host. Original history finding remains open. |
| Current funded customer and owner flows | Local scheduling, signing, replay and accounting contracts pass; upstream funded receipts are historical | Current schema23 Signet/Devnet and betanet/Mainnet acceptance, both directions and owner payouts, with exact on-chain/ledger comparisons and no duplicate sends. |
| Clean Ubuntu installation | Source/packaged private-config setup and signed updater implemented; scoped Ubuntu x86_64 permission/routing checks pass; AWS login refreshed and fresh host provisioned | de00bff actual x86_64 install/repeat/reboot and private-state preservation independently PASS; source-preservation check passed172 tracked files. Abrupt interruption coverage and sustained operational readiness remain separate gates. |
| Independent backup and restore | Current local real-restic financial restore passes | Current funded restore on an independent host, key/attempt/ledger equality, source fencing and safe resumption. Do not count same-host fixtures as off-host acceptance. |
| Customer wallet | Connection-free payment instructions and browser fixtures exist | Actual Solana Pay wallet-app signing, payment association, reload/error/refund acceptance. User deferred wallet availability. |
| External alerts | Existing monitor/diagnostic evidence is scoped | User-selected destination, delivered failure/recovery notifications and independent outage detection. User deferred destination. |
| Production signing trust | Review source published; no production trust established | Designated key holder, independently published/pinned public key, exact artifact verification and distribution acceptance. User deferred ownership. |
| Independent security approval and activation | Standard scan and18-file diff complete; subsequent projection patch has scoped static PASS | Close native-history and dependency applicability gates, obtain final current-release verdict, then explicitly verify public-access policy before activation. A partial scan or scoped PASS is insufficient. |

Current deployment check: isolated Ubuntu source installation at `de00bff`
passed native/browser/restic builds, both Mainnet history providers, independent
backup initialization and pinned ECX snapshot synchronization. Private config
creation and unchanged retry passed. One finalized 0.01 SOL deposit is confirmed
by both providers; installer exited0, services started, website HTTP200 and saved
ATA attempt bytes stayed identical. Worker later paused on RPC rate limits;
readiness recovered. Actual reboot and repeat installer passed with unchanged
configuration/key/attempt hashes and HTTP200. Independent verifier PASS for installation/repeat/reboot; FAIL current runtime
readiness because OnFinality verifier returns HTTP429/-32029 (Alchemy HTTP200).
Sustained load and funded customer acceptance remain open.
See RESUME for exact command IDs.
The prior funded deployment is stopped and preserved. Do not overwrite its ledger,
reuse retired custody or treat old schema tests as current. Details,
source hashes and test scope are in [RESUME.md](RESUME.md) and the records below.

## Config update and wallet replacement (2026-10-22)

Owner ECX receiving-address support: scoped PASS for offline validation, legacy
xpub behavior, custody refusal and real executable configuration import/update
classification. Rebuilt application and full local ConfigureCheck pass; independent
`owner_address_review` source/evidence PASS. Existing production gates remain open;
this change has not been deployed or tested with live funds.

Implemented `sudo ./build/update-config.sh`, reading the protected record before
or after initialization. Supported operational edits retain custody. Replacement
archives keys, the ledger, fence and recovery records; it never sweeps old funds.
Initialized/bound custody requires two new wallet identities; unresolved financial
work and partially provisioned ledgers refuse replacement.

PASS: current application rebuilt using the committed Operation baseline (the
unrelated working-tree Operation/Internal.hs refactor remains untouched), complete
local ConfigureCheck contract with the real rebuilt executable, private-file and
directory interruption/replay fixtures, and disposable PostgreSQL retirement and
fresh-provisioning contracts. Shell syntax and whitespace checks pass. Separate
`config_rotation_verifier` PASS for scoped static implementation review, including
prevalidation, private archives, database receipt binding and retry isolation.

NOT VERIFIED: full Ubuntu/systemd rotation, reboot/interruption at every installer
phase, or a funded replacement. No live deployment or custody was changed. This
scoped review does not change the production gates above. Evidence is in
`.audit/installer-update.tsv`; the existing incomplete capability refactor is not
included in this change or its executable validation.

## Historical verification records

## Scoped repair and owner-fee Flow composition (2026-10-14)

PASS local checks: build; full bridge suite (250 groups/15,609 cases, two expected
mutation failures); positive/37 negative compile checks; six fresh PostgreSQL
contracts (server, ledger, complete-draft resume, Devnet HTTPS, canonical HTTPS,
active Native). Retry, cancellation and owner-fee decisions now compose inside
post-Refl Workflow.interpret. Shared custody steps preserve the operator scope;
only state-preserving conditional/traversal helpers were added. The high-level
request capabilities, critical gate, private effects and financial ordering remain.

The initial HTTPS run was interrupted by a PostgreSQL backend SIGKILL during
COMMIT; its cause was not established. Preserve that failed run as evidence.
The three remaining modes passed sequentially on fresh databases after recovery,
with no source changes. Task cluster stopped. Trace tests cover all eleven forms
and every failure/cancellation prefix; they do not inject faults in every concrete
repair IO leaf. No live deployment, custody or production-approval change.

Baseline `c96ba55`; production two files: 1,706 -> 1,765 (+59); changed tests two
files: 642 -> 700 (+58). No new source files/dependencies. This makes orchestration
explicit rather than reducing total lines. Patch SHA256
`55696beaddd91f00b3922a7a08369d208acdb192a94fe4b2f0281974ad86904d`.
Receipt `/tmp/hot-wallet-composition-receipt.json`, SHA256
`c8d98adcd0fd8c44fed28dea899bc2af01721f94a6c0ae96a9b349cc57f9662a`, binds
70 source/design/evidence artifacts. Fresh independent `flow_composition_verifier`
PASS for this scoped source change: all70 artifact hashes and the frozen patch
match; logs support the stated checks and stopped cluster. The review covers
static equivalence and supplied local evidence, not live or production approval.

## Scoped workflow orchestration (2026-10-13)

PASS: build, bridge suite (250 groups/15,609 cases and two expected mutation
failures), positive/30 negative compile checks, six fresh PostgreSQL contracts
(server, ledger, complete-draft resume, Devnet HTTPS, canonical HTTPS, active
Native). Actual operator resume error and later observation cancellation pause
without sends or changes to saved attempts/bytes, postings and balances. Trace
contracts cover the eight workflow forms and every failure/cancellation prefix;
they do not claim concrete IO fault injection at every signing/broadcast step.

Workflow.interpret constructs orchestration after Refl; private scope instructions
retain exception policies under the existing gate. Internal *Steps capabilities
cannot be selected by request handlers. No API, dependency, schema or live changes.
Baseline `3fe20b5`; production 1,513 -> 1,706 (+193) in two files; tests
6,273 -> 6,480 (+207) in three files; no new source files.
Patch SHA256 `42a8a85fbb73cef2b8e6abb7378a89df7c76996322bb009b457b3fbb35920631`.
Receipt `/tmp/hot-wallet-orchestration-receipt.json`, SHA256
`f280bcbdeb2ffded2c85fce11b6bb66b083fa4c34ed99ec8e13c0e0b2cb2d197`, binds
57 source/design/evidence artifacts. Fresh independent `orchestration_verifier`:
PASS for scoped publication, zero bound hash mismatches, source diff identical.
It checked the intended rejection diagnostics and all six PG mode results without
rerunning builds/services. Injected exceptions prove the stated boundaries, not
exhaustive asynchronous scheduling or every production leaf. Task PostgreSQL
stopped. Broader production gates above are unchanged.

## Scoped capability Flow methods (2026-10-13)

PASS: build, full bridge suite (249 groups / 15,608 cases, two expected mutation
failures), one positive / 23 negative compile checks, and six fresh PostgreSQL
contracts: server observation permissions, ordinary ledger, complete-draft resume,
Devnet HTTPS, canonical HTTPS/owner scheduling and active Native payouts.
The production methods now return indexed Flow; private instructions keep concrete
IO in Critical.hs. The payout workflow composes those methods after Refl, with
explicit checkpoint states before signing and sending. Tests reject omitted
checkpoints/capabilities. The trace carrier exercises the same interpreted workflow
but does not execute production IO; process contracts cover their stated fixture
scope. All prior method bodies retain financial/exception ordering.

Baseline `cd5b429`; four source files, no new files. Production 1,521 -> 1,513
lines (-8); tests 438 -> 483 (+45). Source patch SHA256
`b51d4307258a9c93da6a4dd14f481b0c721709d0cd660ef85bcc9b439a3a7052`.
Receipt `/tmp/hot-wallet-methods-receipt.json` SHA256
`7b68382f5d10b78676191812cf1f235372033c65f99bda126ba0c4fdfdc1ee59` binds
source, design docs, test logs and observed exits. Separate
`capability_split_review`: PASS for scoped publication after verifying all 48 bound
artifacts and all 23 negative diagnostics. No independent test rerun or production
certification is claimed. No live deployment, funds or production approval changed.
The temporary PostgreSQL cluster is stopped.

## Scoped typed payout Flow (2026-10-13)

Build, bridge suite (249 passing groups / 15,608 cases), pinned library properties
(15 groups / 140,001 cases), positive compilation and all 15 negative type checks
PASS. Three disposable PostgreSQL/HTTPS modes PASS: Devnet signer/recovery,
canonical signer/owner scheduling, and pending Native work alongside Wrapped work.
The canonical fixture now gives the dedicated history reader its actual local RPC
URL; its earlier port-1 timeout was a fixture defect. Production checks were not
weakened. The Flow trace contract covers three branches and every failure/cancellation
prefix; it does not directly execute every private interpreter IO effect.

Source starts at `424c1a4`; dependency is operation-capabilities 0.1.3.0 at
`86c5b86078bc6fe9b9130a28d9de600a339f6221`. Production changes total +50 lines in
two existing files; tests +90 lines in three existing files. No new source files.
This enforces stage ordering, not new financial authority, rollback or replay.
Exact source/log hashes and command outcomes: `.audit/severity.tsv` and
`/tmp/hot-wallet-flow-receipt-final.json`. Separate `flow_refactor_review` verdict:
PASS for this refactor/publication; implementation diff SHA-256
`468222b65315b363e2239494d86d5db508ffafe186bfccb9275a55828d1a3de6`.
No deployment, funds or broader production acceptance changed. Test database stopped.

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

## Durable payout rounds (2026-10-10)

Local verification PASS, but separate source review FAIL: the capacity rule does
not preserve headroom across round timing and opposite-direction traffic. Payout
work remains unpublished. Three unignored QuickCheck regressions now reproduce
all three counterexamples. The representable-maximum case is now corrected and
passes; timing/shared-fee cases remain RED. A fourth regression preserves usable
closing capacity: net 9 plus net 91 must fit inventory 100 and exactly two fee
allowances. The full lifecycle module currently has 45 passing checks and two
failing release blockers (not expected failures). Strict
batching needs durable shared closing-capacity reservations. No minimum-order,
or maximum-wait policy change has been authorized. Refund exemption was subsequently
approved and is being verified; see the immediate-refund checkpoint below.
Record thresholds and configurable hours reach runtime policy and the customer
interface. Schema 23 seals all eligible per-asset members and totals, retains the
previous interval across restarts/configuration changes, and requires membership
at preparation and signer evaluation. Already admitted settlement/recovery continues.

A below-threshold quote must leave the slot, inventory and fee budget for a future
threshold-completing order. The real database regression rejects a too-small final
quote without writes, then accepts the closing order. Existing idempotent requests
retain their saved terms. Pure tests cover both assets, exact capacity boundaries,
fee balances and daily ceilings. The interval is not a maximum waiting-time promise.

Build-all, 224 local property checks and payout/default/server/TLS/setup PostgreSQL
contracts PASS. These use disposable fixture keys and a local private database;
all test services are stopped. No live ledger/funds changed, no historical ledger
was converted, and no Ubuntu/funded/independent-host release gate is closed here.
Evidence: `.audit/payout.tsv`. Production and remaining installer/owner/Cloudflare/
manual-wallet/alerts/release-signing/security-review gates stay open.

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

## Configured customer links (2026-10-10)

Record setup now validates and publishes externalLinkOrca/externalLinkSolscan to
interface.json, and the browser uses the configured token explorer. Missing
optional explorer fields retain the network-specific fallback. Solscan must name
the configured mint; Orca validation checks host/address syntax, not liquidity or
on-chain pool contents. Scope evidence is recorded in .audit/layout.tsv. This
does not implement automatic owner sweeps or close payout/release gates.

### Critical evaluator readability

PASS (scoped): flatter dispatch and named local checkpoint steps preserve the gated
authorization/signing sequence, cleanup and timeout. Separate source-equivalence
review passed; the full local bridge-test suite passed on HEAD plus only this change.
Evidence: Docs/.audit/layout.tsv. Production gates remain unchanged.

### Unknown-signature cancellation and signer gate

Production review found a cancellation gap: a lost/withheld signer reply can leave
valid bytes outside the ledger. Cancelling that preparation could then permit a
second payment. Complete drafts are now refused before cleanup or generation
advance; incomplete-draft cancellation remains available. Full safe recovery of
complete drafts and review of historical cancellations remain FAIL/open.
The finite signer-gate model passed 61,745 states and three deliberate faulty
lock transitions were rejected. This does not close whole-system security review.

OPEN: native RPC server authentication/local port ownership. Current managed
loopback HTTP does not prevent another local UID from impersonating a stopped
node. Require an enforced boundary and restart/adversarial acceptance; client
passwords and chain identity checks alone do not close this finding.

### Managed RPC boundary verification

PASS (scoped): the managed-node guard blocks other socket UIDs on fresh IPv4/IPv6
loopback connections, preserves unrelated nftables tables, survives cold boot and
ordinary firewall/guard reload/restart, and stops dependent services on invalid
rules. Re-enabling an inactive guard refuses running worker/signer services.
Configure-only Cabal checks passed on an isolated published-source candidate.
Tests used disposable Ubuntu 24.04 socket and service fixtures, not a real node.
This supersedes the managed-path portion of the native RPC finding above; external
node authentication, real-node/full-install acceptance and the overall production
security gate remain open. Initial standalone-client quiescence remains required.

### Historical cancellation successor guard

PASS (scoped): every historical cancelled generation must have no saved draft
before it can permit a successor or earned-reserve release. A completed cleanup
and absent attempt are insufficient. Full isolated bridge-test passed; disposable
PostgreSQL default contracts and separate complete-native-resume refusal passed.
The latter retains exact resume and unchanged ledger/reserve assertions without
unsafe fixture cleanup. Expiry/cancellation fixtures now use genuinely undrafted
work. Production source has no net added lines. Evidence is in .audit/layout.tsv.

Still OPEN: audit/quarantine already-created historical successors or released
reserves; implement safe recovery of complete drafts with unknown signing outcome.
These tests are local contracts, not funded-chain or whole-production acceptance.

### Historical cancellation quarantine

PASS (local scope): any cancelled preparation with non-NULL draft_json now blocks
new intake, ordinary/replacement signing, rebroadcast authorization and new
spending, including already-admitted successors. Reads, Pause and late signer-byte
retention remain available. Operator actions using readOperator also stop; this is
not a claim that every recovery action remains usable. No automatic repair or
override is provided. Fresh schema installs include a matching partial index;
existing ledgers need that index for equivalent performance, not correctness.

The isolated executable build and both fresh PostgreSQL contracts passed. The
historical fixture preserves schema constraints and checks refusal without balance
or sequence changes. Replacement/rebroadcast coverage checks early refusal, not
fully prepared pending flows; released-reserve coverage is source-reviewed only.
See .audit/layout.tsv. Historical funded-ledger reconciliation, safe complete-draft
recovery, independent security review and production acceptance remain OPEN.

Address configuration validation: scoped PASS. Hostnames require nonempty labels
of at most 63 characters without edge hyphens; use lowercase names without a
trailing root dot. IP literals use pinned iproute1.7.15 plus an ASCII grammar guard.
The isolated configure contract rejects 19 malformed/unsupported host/IP records
before setup publication and accepts IPv4 and three IPv6 forms. This is syntax
validation, not proof of DNS ownership, reachability or public-address routing.

### Immediate-refund implementation checkpoint

Implemented the approved refund exemption in Store/Projection/schema: immutable
refund obligations enter the queue without round membership; they are excluded
from round totals/clocks and forbidden as round members. Preparation's database
trigger and signer read accept only that refund-specific exception. Conversion
and earned payments still need round membership. Refund priority does not bypass
active chain serialization or source/custody/backup/fee checks.

Cabal exe:ecx-store-check build PASS (GHC9.14.1, one job). Actual disposable
PostgreSQL payout contract PASS: Native9 refund below threshold50 during48h wait,
unchanged rounds, queue eligibility, preparation and signer decision. Default
PostgreSQL contract PASS after updating the obsolete SeedScanAttempts fixture to
stop creating a refund round. Covers refund/accounting, rollback, replay, roles,
backup/restore and existing in-process boundaries. Read-only verifier PASS for
source scope. Add opposite-chain delayed-refund and direct invalid refund-round
insertion cases before calling the exemption fully accepted.

Full ecx-bridge executable build is NOT verified: assets hook selected native
ghc-pkg9.14.1 for JS GHC9.12.2 despite source specifying matching --with-hc-pkg.
Repeating with cached asset paths did not fix it. Direct browser build with explicit
matching --with-hc-pkg passed compiler selection but lacked emcc on its PATH.
Investigate cached hooks/environment; no source workaround or compiler downgrade.
All invoked build/test sessions are terminal; disposable PostgreSQL stopped.
No live services, funds, deployment, commit or publication changed. Production
capacity regressions and independent release gates remain open.

### Full application build and process verification recovered

The JS/native ghc-pkg mismatch was a stale generated setup-hook executable, not
an incompatibility in current source. Deleted only the generated assets setup
executable and SetupHooks.o/.hi, then reran the same one-job Cabal build using
existing Cargo/browser caches. Source, compiler pins and dependency locks unchanged.
Cabal exe:ecx-bridge including GHC-JavaScript browser PASS; actual rebuilt executable
HTTP/assets process contract PASS; HTTPS signer process contract PASS (auth,
certificate refusal/rotation, serialization, repeat authorization, replay/recovery).
These use disposable PostgreSQL and offline fixtures, not live chain acceptance.
All processes completed and disposable database stopped. Payout capacity failures,
refund additional cases, independent security and remaining deployment gates stay
open. No live funds/services or GitHub publication changed.

### Refund acceptance and transferable reservation model

Both-direction refund acceptance PASS in real disposable PostgreSQL with nonzero
thresholds and active48h clocks: Native9 and Wrapped7 reach signer decisions;
round totals/clocks stay unchanged. An otherwise valid matching single-member
refund round is rejected with exact23514/membership-mismatch and rolls back.
Existing conversion delay/direct-preparation refusal controls remain. Separate
read-only review PASS for these additions. Test processes and database stopped.

Candidate model now transfers virtual closing capacity to pending quotes instead
of counting both. Unconditional solvency retains all actual principal and fee
holds; conditional closing-capacity preservation covers every non-refund-loss
transition. Independent progress property requires an intact, funded below-
threshold group to admit a legal closer. Original20/40 exact closer now passes.
One failed deposit's source-chain contingency is tested in both directions with
30/40 or20/60, followed by refund payout and usable replacement. Without that
contingency, real refund fee expenditure may require replenishment; competing
admission must refuse, and actual liabilities remain protected. No claim of
unlimited refund-failure tolerance. This test-only model is NOT ledger integration.
Final lifecycle source-run: 50passing/2failing (the two unchanged
production regressions);1000 modeled histories pass. Late receipts, fee-policy
changes, source reorgs, durable ownership and backup/restart still need refinement.
No production code/funds/services/publication changed in this checkpoint.

### Liability-based cohort membership (partial integration)

Projection.payoutCohort now unions pending quote reservations with ALL unassigned
nonterminal non-refund payment roots, including reviewed/source-restricted
conversions and owner withdrawals. Sealed membership excludes work permanently.
Readiness is a flag, not a membership filter. AdmitPayoutRounds requires every
member ready under the deployment lock before sealing. Original ready projection
is derived from this query. Separate source review PASS for ordinary lifecycle
membership; no unsafe disappearance found in inspected paths.

Build exe:ecx-store-check PASS; focused actual PostgreSQL payout contract PASS,
including threshold-met round blocked by pending quote, then that promise removed
by authorized refund and net99 sealed unchanged. Database stopped.
Full default PostgreSQL contract FAILS payout_round_not_due. The new barrier
changes the prior suite's ready-only admission behavior; identify exact failing
scenario and reconcile admission plus cohort semantics before updating fixtures.
Do not mark default suite PASS or simply weaken the check. Existing two pure
capacity regressions remain. This is unpublished partial integration, not a fix
for all capacity/spending paths; no live funds/services changed.

Minimal complete design still needs durable per-asset active-cohort policy
(threshold, closer fee assumptions, queue/epoch rules) so config changes cannot
invalidate ownership. Existing reservations/immutable payoutMembers may suffice
for membership. Admission must compare cohort requirements BEFORE/AFTER so a
closer consumes its own virtual allocation; ordinary spending must see all holds.
Forbid further cohort additions once projected threshold reached, include owner
withdrawals, and add reviewed-conversion retention/expiry contract tests. A
mutable current config is not a substitute for saved cohort policy.

### Whole-asset sealing barrier corrected

Exact default-contract failure located at historical conversion preparation:
ready Wrapped93 was blocked by five independent pending Wrapped9 quotes and a
separate reviewed Wrapped93 obligation, despite immediate threshold1 policy.
This is a real scheduling regression, not a reason to release/expire fixtures.
Separate verifier agreed: remove whole-asset allReady barrier; retain complete
liability projection for capacity; implement explicit durable batch assignments.

Removed premature barrier. Added Opaleye-only fixture assertions that pending
quote appears, terminal refund removes its conversion promise, reviewed obligation
remains false-ready, and independent funded conversion remains true-ready.
No liability was dropped/expired to make acceptance pass. Both payout and default
actual PostgreSQL contracts now PASS; build PASS; temporary PostgreSQL stopped.
This restores prior scheduling, NOT a resolution of the two production capacity
regressions. The model's single-open-group scope must expand before integration.

Implementation correction: multiple stable cohorts per asset are necessary for
independent ready work. Persist immutable member assignments plus bound policy
(threshold/closer fees/queue assumptions). Stop additions to a projected-full
cohort; later quotes enter another cohort. Reviewed members retain assignments.
Seal only each cohort's own resolved members, and combine eligible cohorts under
the shared asset interval. Global resource calculation must include every cohort;
only admission to the owning cohort may consume its virtual closing allocation.
Owner withdrawal treatment and fee-spending consumers need explicit coverage.
No live funds/services, deployment or GitHub publication changed.

### Multiple cohorts and immutable policy foundation

Candidate model now leaves projected-full cohorts alone and opens a new cohort
for later offers. Independently funded cohort can pay while earlier full cohort
awaits receipt. Admission has append-only existing-member assertion; conditional
progress targets oldest deficient cohort per asset. Global solvency/conservation
still checked.1000 random histories pass; full lifecycle 51pass/2fail
(the two unchanged production regressions). Add explicit full-cohort-unchanged
assertion and tight-slot refund recovery before considering model complete.

Added UNUSED schema foundation: payout_cohorts saves threshold, Native/SOL fee
allowances, queue limit and interval immutably. payout_assignments requires exactly
one order/withdrawal FK and unique subject ownership. Typed Opaleye mappings and
closed schema contract test mutation/deletion, duplicate ownership and no-subject
refusal. Cabal store-check build PASS; actual PostgreSQL payout/default PASS.
No runtime admission/sealing consumes these tables yet. This is not capacity
integration, current-funded acceptance or populated-cohort restore verification.

Separate verifier PASS only for foundation. Required BEFORE wiring:
1. Add durable creation ordering (critical sequence), not lexical/random IDs.
2. Bind saved cohort policy and complete membership to sealing; prohibit partial
   sealing while allowing the defined aggregation of eligible cohorts per interval.
3. Enforce member asset and timing (not already sealed; no additions once full).
4. Define coexistence of saved fee assumptions/queue limits after config changes.
5. Verify populated-cohort backup/restore and schema compatibility. User requires
   one schema only: reject unsupported ledgers, do not implement migration.
6. Extend member cases to owner withdrawal, both-subject rejection, wrong asset
   and seal boundaries, then integrate before/after reservation accounting across
   ALL spending operations. Keep production capacity failures visible until fixed.
All task processes terminal, disposable PostgreSQL stopped; no live changes or
publication. Do not deploy unused foundations as a finished capacity solution.

Cohort ordering/asset-binding follow-up: store-check build and actual PostgreSQL
payout/default contracts PASS. Runtime capacity integration and populated-cohort
restore remain FAIL/unverified; no production gate is closed by this schema slice.

Closing-capacity arithmetic / assigned-work projection: scoped verifier, model
1000 histories and actual PostgreSQL payout/default PASS. Two production capacity
regressions remain FAIL; runtime integration is not complete. See RESUME.

### Runtime payout admission checkpoint (supersedes prior capacity failures)

Customer cohort admission/scheduling, original regressions, fee-policy increase,
1,000 model histories and real PostgreSQL payout/default contracts PASS, including
populated-cohort backup/restore. Refunds bypass batching without advancing its clock.
See RESUME for exact scope. All-consumer spending protection, owner admission and
DB seal/timing linkage remain FAIL/pending; production readiness remains FAIL.

Closing reserves now protect treasury classification and source-loss capital.
Scoped review, lifecycle/model and actual PostgreSQL payout/default checks PASS.
Owner admission, additional unreserved payment fees and DB seal enforcement remain
pending; see RESUME. Production readiness remains FAIL.

Additional preparation/retry/refund fees now protect closing reserves while reusing
valid existing holds. Application/store builds, lifecycle/model, real PostgreSQL
payout/default/process/restore checks and scoped source review PASS. Owner admission
and DB seal/timing remain pending. See RESUME and .audit/payout.tsv; not prod ready.

Owner fee reservation and post-cancellation capacity now PASS scoped source review,
application/store builds, lifecycle/model and actual PostgreSQL payout/default/
process/restore checks. Existing fee table reused; no new endpoint or service.
DB cohort seal/timing enforcement and broader production gates remain pending.
See latest RESUME and payout audit receipt; this is not production completion.

## Cohort sealing checks (2026-10-11)

Scoped PASS: complete mapped cohorts, saved threshold/interval, no assignment to
full/sealed cohorts, no new terminal member; actual PostgreSQL payout and full
process/backup-restore contract passed, session61585 exit0. Separate read-only
verifier PASS. Refunds remain outside batching with other safety checks retained.
Production remains FAIL: unassigned-live-work detection and other recorded gates
are unfinished. No publication or live deployment occurred.

## Complete liability accounting (2026-10-11)

Scoped PASS supersedes the unassigned-live-work gap above: complete projected
liabilities must match cohort membership before capacity/admission calculations.
Build and PostgreSQL payout/default/process/backup-restore PASS (77578 exit0),
separate runtime source review PASS. Missing-assignment rejection leaves compared
financial records unchanged. Production release remains FAIL on other open gates.

## Owner configuration (2026-10-11)

Scoped PASS: owner destinations persist in typed runtime configuration, with strict
parsing/validation and legacy-disabled default. Focused configure contract passed
(session31425 exit0); independent source review PASS. Automatic owner fee scheduling
is still unimplemented and remains FAIL. This is configuration retention evidence,
not proof of payouts or production readiness.

## Automatic reservation ledger (2026-10-11)

Scoped PASS: Earned-only automatic reservation, pending-work duplicate protection,
shared fee/cohort admission and unchanged manual behavior. Build + real PG payout/
full process/restore PASS59071; separate source review PASS. Automatic worker
scheduling and configured recipient resolution remain FAIL/unwired.

## Automatic owner worker integration (2026-10-11)

Worker wiring and public descriptor resolution are now implemented. Existing
payment candidates take priority; optional funding shortages skip owner sweeps.
Full Cabal regression PASS63972, prior real PG payout/default/process/restore
PASS49387; separate source review PASS for priority and narrowly normalized native
preview shortage. These checks do not establish funded owner end-to-end acceptance,
which remains FAIL alongside the other production gates. No live/public activation.

Restart follow-up PASS33933: both assets preserve exact automatic withdrawals
across writer restart and changed destination/limits, with enough earned funds
remaining to exercise duplicate prevention. Rescheduling leaves financial/archive
records unchanged; cancellation restores nonzero balances. Separate reviewer PASS;
real PG payout and full process/restore passed. Worker/funded acceptance stays open.

## Optional hosting (2026-10-11)

Configuration persistence and application regressions pass (full Cabal and app/
store build, PG payout/default/process/restore93480 exit0). The new pinned tunnel
installer now has scoped Ubuntu24.04 ARM64/systemd acceptance: fresh/repeat start,
private credential access, wrong-identity refusal, SIGKILL expiry without restart,
recovery, real reboot and restore-blocked reboot PASS. Permission, changed-token
and binary-integrity refusals also PASS. Separate verifier PASS for this scope.
The lifecycle harness used an inert connector and mocked HTTP identity; the actual
pinned cloudflared binary separately passed version/token-file compatibility.
Live Cloudflare routing and whole-host installation remain FAIL/unverified.
The disposable 1GiB VM was deleted; no public service was activated.


### Real native owner derivation compatibility (2026-10-11)

The actual ECX betanet v31.1.0 node accepted the configured public xpub's
wpkh(xpub/0/0), retained the descriptor/checksum form, derived exactly one address,
and classified it as an unowned witness_v0_keyhash through getaddressinfo and
decodescript. The temporary main-chain node had networking disabled and a blank
private-key-disabled wallet; no descriptors were imported, no funds moved, and
its process/data were removed. Exit0 receipt89792 and hashes in .audit/payout.tsv.
This validates actual node RPC compatibility, not the Haskell worker-to-signer
flow, restricted production credentials, synchronization or a funded owner payout.
Those acceptance gates remain open. Separate read-only verifier PASS for the
recorded RPC-compatibility scope.


### Automatic owner reservation through HTTPS signing (2026-10-11)

The existing TLS/PostgreSQL contract now begins with ReserveAutomaticFees,
checks the saved three-unit destination/amount, admits its batch and verifies its
payment candidate before preparing and signing through the actual HTTPS signer.
Independent Ed25519 signing over the SDK message checks the returned bytes.
Concurrent requests, authentication/certificate rotation/refusal, stale-custody
refusal, duplicate recording and checkpoint checks remain intact. No extra test
program or production capability was introduced.

Both Canonical Mainnet and Devnet profile contracts PASS (build/run77616 exit0).
The new loopback limiter exposed a test burst: checkpoint assertions received429.
Requests now wait2.1seconds, preserving exact409/error assertions; no limiter was
relaxed. Compiler source fingerprint ff1990fdf7e27e970ec144bacaecb36c matches the
final source, including pacing. Separate source/execution verifier PASS. Temporary
PostgreSQL stopped and socket directory removed. RPC/funds are fixtures; automatic
worker scheduling, native signing and funded owner payouts still require acceptance.


### Release-wide guard review (2026-10-11)

Separate source review found and verified fixes for two P2 setup defects:
initialization omitted payout cohorts/assignments from its empty-ledger check;
owner configuration allowed custody ATA/mint destinations that later paused the
worker. Initialization now rejects cohort residue. Runtime and record import
reject custody owner/ATA/mint before installation material publication.
Build93898 and configure plus real PG fresh/event-residue/cohort-residue contracts
61965 PASS; disposable PostgreSQL cleaned. Source reviewer PASS for both fixes.

Codex Security installation was completed through the app and its tools appeared;
prior not-installed notes are historical. The full plugin scan is still pending.
Fresh cargo-audit checked148 dependencies against RustSec7eebec69: no vulnerability
matches, bincode maintenance warning retained. Cabal/readFloat advisory pages remain
unchanged. Gitleaks flagged only ChainCheck's public xpub fixture in the production/
test diff; new tunnel script had no flags. This is not a whole-repository secret
scan or a waiver of dependency/security gates. Public service remains off.


Codex Security Deep Scan invocation failed before a scan started: "Deep Scan
cannot safely start a read-only worker: the parent must provide a managed
filesystem permission profile." This thread currently has unrestricted filesystem
permissions. Do not retry unchanged or claim a scan is running/passed. A managed
permission-profile session is required for that plugin gate. Daybreak access check
also returned not_granted (advisory only, not the launch blocker). The installed
plugin remains available; temporary UI driver was stopped.

### Current security gate (2026-10-11)

The Standard Codex Security scan dd391a4d-041c-4fb7-a16e-12378cb8f1ad completed
against1c8da93. Production security remains FAIL: Native-history nonprogress is
confirmed and unresolved; dependency/spool uncertainties and real deployment
acceptance remain open. The Low test-log issue was corrected in0bf22c0 with
focused process/PG tests and separate source review. The earlier Deep launch
failure is not a Standard-scan failure or evidence of a passing security gate.

Backup-spool path race subsequently confirmed and corrected: Ubuntu24.04 GNU
install reproduction, least-privilege replacement, fresh/repeat controls, shell
syntax and separate patch review PASS. This is a scoped helper check on ARM64,
not the pending full x86_64 clean-install gate; larger Native-history recovery and
remaining dependency/security gates stay open.

Native freshness checkpoint: build, full PostgreSQL/process/backup contract and
bridge-test PASS; separate candidate static review PASS. Stale scans now refuse
intake without adding an operator pause; adjacent-output custody checks reuse one
proof with per-output checks and revision fences intact. This does not close the
native-history finding or certify unbounded runtime. See RESUME.md for evidence;
real-node acceptance and all broader production gates remain required.

Current change review: Codex Security diff scan
243ed26d-0a00-416f-88aa-abdb4ce9e8b9 sealed for 1c8da93..c942b3b, covering all
18 changed files. No new confirmed finding; history-entry conflict-array resource
impact remains deferred (partial coverage). Original Native-history finding and
production security gate remain OPEN/FAIL. This is not fresh-install, live-network
or whole-application certification. Details and next proof gap are in RESUME.md.

## Payout interpretation follow-up (2026-10-13)

- 2026-10-13: payout dispatch moved from runPayoutStep into the private
  PayoutCommand Operation.interpret after eqT/Refl. Pure resolution creates
  deferred WorkerEffect actions; the existing critical gate executes them.
  Build, 249 QuickCheck groups/15,608 cases, positive and 15 negative type checks,
  and three disposable PostgreSQL/HTTPS modes PASS (Devnet, canonical, active
  Native). The trace oracle checks sequencing and actual pure compilation;
  concrete effects remain covered only to the stated integration fixture scope.
  Net +29 production/+6 test lines, no new files. No live deployment or funds
  changed; task PostgreSQL stopped. Receipt: /tmp/hot-wallet-interpret-receipt.json.

Separate payout_interpret_verifier PASS for scoped source publication; reviewed diff SHA256 52c96ebcec3d324c60d0099f17bf0e44c9159d76cfc5b8ee2d419f948f246f0f and receipt SHA256 91ba4766de9f5c65b98feb126aaf1574453b28ef60c21c73cc0b14c41227d316. No production certification.

## Whole payout workflow interpretation (2026-10-13)

- 2026-10-13: whole payout `F.do` now lives inside PayoutWorkflow.interpret,
  after eqT/Refl. The helper returns the pure interpreted Flow; the worker rejects
  mismatch and evaluates under the existing gate. Leaf actions remain unchanged.
  Build, 249 QuickCheck groups/15,608 cases, one positive/15 negative type checks,
  and three fresh PostgreSQL/HTTPS modes PASS. Added whole-payload mismatch check;
  flow trace still uses an independent oracle, not live financial acceptance.
  Net +15 production/+6 test lines; no new files. Library design guidance and
  compiling example updated separately in operation-capabilities (API unchanged).
  No deployment/funds changed; test PostgreSQL stopped. Verification receipt:
  /tmp/hot-wallet-whole-receipt.json. Separate publication review recorded in DONE.

Separate whole_payout_review PASS for scoped source publication: diff SHA256 556f24fe89f3c512dfe998e2e3a69ca3229f73c3fc242ac6a8d1daf285e2316f; receipt SHA256 5084f89f3957912aa75f09ba1d46eeb79d88910f011074eb2acd3e9d33af9957. All four source/seven log hashes verified; no live or production certification.

## Scoped operator/worker capability split (2026-10-13)

- 2026-10-13: split OperatorWrite into five capabilities and WorkerOperations
  into eight. Actual rank-n request selectors receive only their explicit subset
  through Restrict/withCapabilities inside interpret after Refl. Each payout step
  requires its own groups; the complete F.do requires their union. Concrete IO
  remains private to Critical.hs. A separate comparison found all 31 effect bodies
  unchanged after normalizing capability annotations and the WorkerAction proxy.
  Build and full bridge suite PASS (249 groups/15,608 cases, two expected mutation
  failures). Positive type checks include a composed two-capability request; all
  21 negative cases reject. Three fresh PostgreSQL/HTTPS fixture modes PASS:
  Devnet signer/recovery, canonical signer/owner scheduling, and active Native work.
  Production lines 1,592 -> 1,670 across the three touched files (+78); tests +42
  across two existing files. No new source files, dependency or public API changes.
  This adds checked boundaries rather than reducing source size. No deployment or
  funds changed; task PostgreSQL stopped. Receipt: /tmp/hot-wallet-caps-receipt.json.

Broader production gates above remain open.

Separate capability_split_review PASS for scoped source publication: all five source/29 log hashes verified; source diff SHA256 7294bbacf04c31d46b8014202ab87ba998fee4ea4d4a1a8ae790f3b4c0749541; receipt SHA256 11f2e53407053eb851580e82774b1bb1826cb055b8f0278c2524d878ca00ac3d. All 31 concrete method bodies preserve behavior. No production certification.
