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

1. Complete automatic owner worker-to-signer acceptance for both assets, actual
   native public derivation and funded payouts. Configuration, Earned-only durable
   reservations, duplicate suppression across restart and ordinary payout wiring
   are implemented; their ledger tests do not prove the whole live path.
2. Complete unattended Ubuntu whole-host installation/repeat/reboot acceptance,
   including the pinned toolchain, node, services and backup destination. Source
   staging and component tests are narrower evidence. Only install.sh is the human
   server entry point; external prerequisites must be independent input strings.
3. Complete optional Cloudflare service and route acceptance. Private token/origin
   wiring, pinned connector, bounded verification lifetime and loopback rate limiting
   are implemented. Track Ubuntu fixture evidence separately from an actual tunnel.
4. Review the complete unpublished candidate, dependencies and exact distribution;
   obtain the independent security verdict, then commit/publish the reviewed tree.
   Preserve source/ledger backups and do not reuse upstream acceptance receipts.
5. Finish current-version real wallet/chain/restore acceptance and the deferred
   external alerts and production release-signing trust. Keep public ingress off
   until all production gates pass. No live custody or schema replacement here.

Do not repeat completed financial slices without a new concern: closing capacity,
owner admission/cancellation, cohort sealing and complete liability accounting have
passing current PostgreSQL contracts. Refunds bypass batching; ordinary swaps retain
saved thresholds/intervals. See the scoped evidence below. Use one build job and
stop/remove temporary VMs after acceptance work.

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

The earlier cleanup supported schema 22. `src/schema.sql` replaced all historical SQL files;
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
The subsequent payout-round implementation uses schema 23. Its admission guard
preserves closure capacity instead of raising the queue cap or waiving thresholds.
Build-all, 224 local checks and all five disposable PostgreSQL/process modes pass;
review evidence is recorded in .audit/payout.tsv. Fresh source review FAILS: an
unfunded quote cannot borrow threshold credit from a round that can seal without
it; opposite-asset traffic must not spend another batch's closure headroom; one
closing order may not reach an extreme threshold. User policy choice is pending.
No live ledger, custody or deployment changed; production gates remain FAIL.

Installation URL validation is independently reviewed and tested; see DONE.md and
.audit/layout.tsv. Unpublished payout work still fails liveness review for pending
quote/round timing, shared fees and extreme thresholds. User policy choice is
pending; do not treat its passing fixture suite as release acceptance.

Payout review counterexamples to preserve for the selected policy's regressions:
- Threshold 100, per-order Native/Sol fee bounds 10, operating balances 20/20.
  Ready wrap W(net100) holds Sol10. Small unfunded A(net1) borrows W's threshold
  credit and reserves the remaining Sol10. W seals/settles before A funds, spending
  Sol10. A then funds and keeps Sol10 held: no fee capacity remains for a closer.
- Small funded wrap A(net1) holds Sol10. Two threshold-completing unwraps can
  successively consume the Native20 operating balance; A can no longer obtain
  a new closing quote because every quote also needs Native refund/conversion fees.
- Threshold=maxBound Int64 exceeds one legal order's maximum net after its 1%
  fee. With a final reserved slot and tiny existing funding, no closing quote fits.
No source/config/operator changes or reorgs are needed for these cases. Do not
solve them by dropping a threshold, increasing a finite cap, or weakening holds.

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

### Payout closing-capacity implementation checkpoint

The partial intake rule now computes ceil(shortfall / maximum representable net),
using the actual rounded 1% quote and Integer intermediates, instead of assuming
one closer. It reserves the corresponding slot count and fee multiple. No payout
policy change, runtime deployment or public-source publication occurred.

Do not restore the attempted local no-ready-credit rule: separate review proved
it admits net9 with free inventory100, then refuses its exact net91 closer with
free91; fee headroom has the same problem. That change was reverted. Durable
closing reservations need an owning group: genuine closing quotes consume its
reserved room, while other groups/directions cannot. Funding, expiry, round seal,
settlement, refunds, operator costs, retries and restart must preserve ownership.
The current waiting-credit query is deliberately retained until that design is
implemented; its two known release blockers remain unignored.

Final source-run lifecycle evidence: /tmp/ecx-payout-lifecycle-closers.log, exit1,
45 passing checks and exactly two known failures. lib:ecx-bridge/lib:store built
with Cabal GHC9.14.1 -j1 --offline. No PostgreSQL or full application suite run for
this partial change. Logs/hashes in .audit/payout.tsv.

Address validation checkpoint: isolated HEAD plus installer IP/hostname checks
passed configure-only Cabal acceptance (session78214 exit0); no live services or
funds changed. Test/build processes ended. Payout work remains excluded, with two
red regressions; AWS authentication and production security gates remain open.

### Batch ownership model checkpoint

AWS ecx-dev STS still refuses expired credentials; no fresh login process started.
Production remains at published 6de7257; this turn edits tests/evidence only.
LifecycleCheck now has a candidate batch model: stable per-asset quote membership,
no seal while member quotes are unresolved, expiry restores closing capacity, and
settlement consumes only owned reservations. Separate Native/SOL allowances,
asset conservation, legal offer bounds, and single-open-group ownership are checked.
1000 ordinary histories pass with measured expiry/settlement/both-assets/multiple-
closer coverage at threshold100 and Int64max. This is not Store acceptance.

The explicit wrong-amount case FAILS: two pending Wrapped net50 quotes fit their
ordinary allowances; replacing one with a funded Native49 refund creates closing
needs in both assets. The candidate has no contingency reservations for this.
Do not integrate it into Store yet. That policy question was pending at this checkpoint; the approved exemption and
subsequent model findings below supersede it. Even an exemption would still need durable ownership,
actual Store transitions, late receipts, reorg/recovery and fee-policy checks.

Final whole lifecycle source-run session79119 exit1: 48 checks pass; two existing
production payout regressions plus the candidate refund-model regression fail.
No tests are marked expected failures. No full application/database rerun, no
new compiler/VM left running, no funds/services touched. .audit/payout.tsv has hashes.

### Approved immediate refunds; corrected model and progress failure

The user approved wrong-amount/late refunds bypassing both threshold and interval;
normal swaps remain batched. Current production WIP does NOT implement this yet.
The test-only model now represents PendingReceipt, ConversionReceipt and
RefundReceipt separately: funded conversions retain both allowances until payout,
matching Store.promoteDeposit; refunds retain only their payout allowance and are
independently payable. Random histories now include wrong-amount receipt/refund
transitions, with measured coverage and conservation checks.

Separate read-only verifier caught a remaining progress failure despite passing
random safety histories: initial20Native/40SOL admits funded net9 but cannot admit
its net91 closer because its virtual reserve is not consumable. Keep the original
20/40 successful-completion requirement RED, not a substituted30/60 example.
A corresponding queue-slot deadlock also remains: nine small funded members plus
one virtual closer fit10 slots but insertion of the actual closer requires11.
These are reasons NOT to adopt the candidate. Finite fees cannot guarantee
unlimited wrong-deposit/refund attempts; distinguish safe refusal, contingency
coverage and ordinary successful closer progress in the replacement design.

Final source-run /tmp/ecx-payout-refund-model.log exits1: 49 passing checks,
3 failing (two existing production regressions plus candidate closer progress).
Randomized candidate histories pass1000 including immediate refunds; this is not
PostgreSQL, funded-chain or production acceptance. No production code changed in
this checkpoint; no publication, service changes or funds moved; test runner ended.
Next: correct usable group reserves and add explicit slot-progress regression,
then implement durable ownership plus refund exemption as one Store/schema change.

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

Read-only reviewer design guidance for next payout fix: a virtual closer is an
owned allocation that a real pending closing quote replaces, not a second customer
counted alongside it. Preserve all funded principal/actual fee holds. A failed
closing deposit uses its reserved source-chain refund allowance; a one-failure
recovery guarantee additionally needs that source fee (Native10 for wrap, SOL20
for unwrap in the model), not necessarily a third pair of allowances. Recycle its
queue slot after refund settlement; simultaneous replacement needs another slot.
Keep ordinary successful closer progress, financial safety, and replenishment
after real refund fee expenditure separate. Do not merely suppress existing red
regressions or adopt this recommendation without executable transition checks.

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
Separate verifier PASS for candidate model with conditional progress: safety and
ordinary closer progress are substantive independent assertions, not suppressed
failures. Qualifications: refund can temporarily occupy replacement's slot as
well as consume fees; add tight-slot recovery after refund settlement. Finite
contingency permits replenishment-dependent progress after wrong deposits, not
uninterrupted closure for every outcome. Store integration/competing spending/
daily limits/late receipts/reorgs remain unverified. No new in-scope counterexample.

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

### Cohort ordering and asset binding

Added immutable positive/unique critical_sequence to cohort policy and its typed
Opaleye mapping. Explicit ordering is tested against reverse insertion order.
Assignment insertion binds the payout asset to the order reservation or earned
withdrawal. Assigned reservation assets/identity cannot change or be deleted;
ordinary phase changes still pass the full payout flow. Exactly-one-subject CHECK
handles empty/both-subject records; withdrawals use a real ReserveFees result.

The first fixture attempt failed payment_root_missing because it inserted a
withdrawal without its payment root; corrected to the closed operation, without
relaxing any constraint. One-job store-check build PASS; real disposable payout
and default PostgreSQL contracts PASS; git diff --check PASS. Cluster stopped,
socket removed. Existing restore suite passed but does NOT yet exercise populated
cohorts. Runtime does not use these tables; two production capacity failures remain.
Next: bind whole cohort membership/policy to sealing and implement before/after
virtual reservations across admission and every spending consumer. No deployment,
fund movement, commit or publication occurred.

Fresh separate verifier: scoped PASS on corrected ordering/asset fixture and
guards. The triggers alone do not close concurrent assignment versus reservation
mutation races: future runtime writes must use the existing exclusive writer and
deployment lock, or add explicit relational locking with a two-connection test.
This is not standalone concurrent database safety or a production verdict.

### Closing-capacity calculation and assigned-work projection

Extracted closingCapacity (inventory, legal closer slots, Native and SOL fee
headroom, all aggregate arithmetic Integer); existing partial capacity check now
uses it. Candidate model checks this production arithmetic against independent
expected headroom after every generated transition: 1000 histories PASS. Explicit
maximum-fee multiplication, empty/full batches and invalid-input tests PASS.
Lifecycle suite remains RED on the same two production capacity regressions.

Projection.assignedPayouts binds pending order IDs, promoted conversion IDs and
owner withdrawals to immutable cohort membership. Actual PostgreSQL payout tests
now assert exact pending -> funded same-cohort membership, source-ineligible
retention, wrong-amount refund exclusion, sealed-member exclusion, withdrawal
membership and real ExpireQuotes removal. Single-job Cabal store-check build,
payout and default PostgreSQL suites PASS. Separate verifier scoped PASS on
calculation/projection and these tests. Temporary database stopped/socket removed.
No deployment, publication or fund movement.

Runtime assignment creation, cohort sealing policy and global hold accounting are
STILL UNWIRED. Next implement them together: admission computes before/after own
headroom while preserving all other cohorts; ordinary spending protects headroom,
while already-reserved customer/refund payments retain access to their actual
holds if virtual closing capacity needs replenishment. readFeeBudget serves both
new spending and reserved preparation, so blindly adding virtual holds there would
block legitimate refunds. Treat current ready-only scheduler as unfinished; do
not publish this work or count projection success as capacity acceptance.

## Runtime cohort admission and refund policy checkpoint

The user's explicit selection is binding: wrong-amount/late refunds bypass payout
thresholds and intervals; ordinary swaps remain batched. Refunds retain the normal
custody, source, backup and signing checks and do not advance payout-round clocks.

Customer admission now replaces the selected deficient cohort's closing allocation
while retaining every other cohort's inventory, queue and fee requirements. Full
cohorts cannot credit later quotes. Future closing fees use max(saved,current)
allowances; owner withdrawals count toward intake queue occupancy. Runtime-created
assignments and policy are persisted atomically with order/withdrawal creation.
Scheduling seals all ready complete eligible cohorts for the asset under saved
threshold/interval rules. Owner reservation still needs its own capacity admission.

Evidence: store-check build PASS; lifecycle checks and 1,000 independent randomized
model histories PASS, including both former production regressions, exact closer,
maximum-size splitting and fee increase. Disposable PostgreSQL payout/default
contracts PASS (session2070 exit0). Default pg_dump/restic/restore compares populated
cohorts and assignments along with the financial records. Historical-terms fixture
now explicitly establishes current-schema membership; this adds no migration or
runtime adoption fallback. Temporary PostgreSQL was stopped and removed.

Separate cancellation_release_verifier gave a scoped PASS for the fee-policy fix
and owner queue counting. This is not a final whole-change/security verdict.
Still pending: all other spending consumers, owner headroom admission, database
cohort seal/timing linkage and fail-closed handling of unassigned live work. Default
subprocess checks used the previous application binary. The current application
also builds successfully (session19924 exit0, one compiler job); its subprocess
acceptance still needs a rerun after the remaining runtime changes. No deployment, fund move, commit or publication.

## Closing reserves: treasury spending and source-loss coverage

New treasury outflow classifications now preserve both actual holds and batch
closing inventory/fees. Source-loss coverage preserves closing Native inventory.
Both use the same max(saved,current) closing-fee calculation as customer intake.
Depleted virtual headroom allows zero debit, but no positive free-capital debit;
negative actual reserves remain negative. Existing classifications/covers replay
without a new capacity requirement. Existing refund authorization is unchanged.

PASS: store-check build, lifecycle suite (including 1,000 model histories), actual
PostgreSQL payout/default suites and populated backup/restore, session3967 exit0.
New PostgreSQL regression proves a treasury outflow affordable before virtual
holds is refused with unchanged balances. Independent read-only verifier scoped
PASS for these changes and zero-debit semantics. Initial overbroad edit was caught
by compilation and restored against the exact prior source hash before testing;
no earlier work was lost. Disposable PostgreSQL stopped/removed.

Remaining capacity work: owner admission and its own fee reservation; additional
unreserved preparation/retry/refund fees; database complete-cohort seal/timing
linkage; reject unassigned live work. This is not production completion or a full
application subprocess acceptance of the latest source. No live custody or
publication changed.

## Additional payment fees preserve closing reserves

Preparation/retry and repeated-refund authorization now share checkFeeReallocation.
Existing valid fee holds remain usable when virtual capacity is depleted. A net fee
increase must also preserve closing fees; missing actual holds are checked first.
Refund authorization computes post-refund cohort requirements, removing only its
own pending/conversion membership. Other members and cohorts keep their reserves.
This changes no refund batching, signing authority, schema, or payment identity.

PASS: store executable build71845, full application build57534, lifecycle tests
(including direct preparation/refund decisions and 1,000 model histories), actual
PostgreSQL payout/default/process/backup-restore suites46130, all exit0. The latter
uses the freshly rebuilt application. Separate read-only verifier scoped PASS.
16 net production lines added across Lifecycle.hs and Store.hs; 25 test lines.
Temporary PostgreSQL stopped and removed. No live payments/deployment/publication.

Next capacity work is owner withdrawal admission: reserve its own execution fee
when creating the withdrawal, protect customer closing inventory/fees/queue slots,
and transfer/release that hold at preparation/cancellation without double counting.
Existing fee_reservations belongs to payment roots and may be usable before initial
preparation; verify the deferred consistency trigger and all cancellation/recovery
paths before choosing this over a new table. Database complete-cohort seal/timing
linkage and rejection of unassigned live work remain open. Production gates FAIL.

## Owner admission, fee reservation and cancellation

Owner and customer admission now share projected cohort resource checks. An owner
uses earned principal, reserves its own chain's execution fee immediately, and
must preserve global closing fees/queue slots and the cohort's closing inventory.
The existing fee_reservations table is reused: initial owner preparation validates
and updates the early hold, cancellation releases it, and retry transfer rules
continue to apply. Ready/unprepared owners require a positive matching-chain hold;
fee rows cannot be deleted or have identity/asset reassigned.

Discretionary cancellation now projects the owner's removal before mutation.
It checks both asset inventories, both fee budgets and exact queue count after
releasing the owner's fee hold and slot. Unsealed customers therefore cannot lose
their closing capacity through an owner cancellation. Sealed work retains its
existing admission and does not need replacement threshold reserves. Refusal leaves
the owner and fee reservation unchanged. Cancellation replay remains idempotent.

PASS: application/store build; full lifecycle and 1,000-model histories; real
PostgreSQL payout/default/process/backup-restore checks (final session8872 exit0).
The new database test proves refusal under reduced queue capacity, unchanged
withdrawal/fee hold, then successful cancellation after capacity restoration.
Database tests also reject fee deletion/reassignment/asset mutation/early release
and zeroing. Separate read-only source verifier passed the admission and post-cancel
resource logic. Fixture clock/100 Native operating funds were moved into initial
setup, preserving original total funds rather than bypassing the new admission.
The new connection-free fixture uses an empty Solana refund field as required.

Production additions for this slice: Lifecycle 1006->1029, Store 3750->3795,
schema 863->880 lines; no new table, process or endpoint. Next: database complete-
cohort seal/timing linkage, rejection of unassigned live work, then the remaining
installer/automatic-owner-sweep/configuration and external production gates.
No live deployment, funds, commit or publication changed. Disposable PostgreSQL
was stopped and removed; full project readiness remains FAIL.

## Cohort sealing verification (2026-10-11)

PASS scoped: immutable cohort policy now governs database round sealing. Reject
partial cohorts, lowered thresholds/intervals, late assignments to full/sealed
cohorts, and newly inserted terminal members. The latter uses an insertion-time
ready check with a row lock; existing members may still settle/cancel afterward.
Refunds bypass batching and never contribute to round thresholds or clocks.

Single-job store build and real disposable PostgreSQL payout/default/process/
backup-restore suites passed (session61585 exit0). Separate read-only verifier
cancellation_release_verifier passed the terminal-member correction and sealing
scope. Source eligibility and coordinated reservation/payment changes continue to
require runtime checks and the deployment lock; arbitrary SQL writers are not a
supported safety boundary. Source/log hashes are in .audit/payout.tsv.

This slice: schema 880->936 lines; StoreCheck 5274->5304. No new table, endpoint or
process; the added view derives immutable payment/cohort links. Temporary PG was
stopped and removed. Next: fail closed on unassigned live liabilities, then the
remaining configuration/install and production gates. No live funds/deployment or
GitHub publication changed; broad schema23 work remains unpublished.

## Complete liability accounting (2026-10-11)

PASS scoped: readPayoutBatches compares all bounded live unsealed liabilities
against assigned rows, including pending quotes and reviewed conversions. Missing
assignments reject with unassigned_payout_liability instead of understating closing
capacity. Production Store grew 3795->3801 lines; no new table/API/process.

Application/store build passed. First default PostgreSQL run correctly exposed
SeedReview's missing cohort; fixture now seeds current-schema reservation and
assignment before promotion. Final payout/default/process/backup-restore passed
(session77578 exit0). Refusal test compares FinancialRecords+ArchiveRecords and
ReadState; retiring the malformed fixture allows admission again. Separate source
review PASS for runtime invariant and ordering; writer lock remains required.
Temporary PostgreSQL removed. Hashes: .audit/payout.tsv. Next: automatic owner fee
sweeps and remaining configuration/install/release gates. Public live access stays
off. Broad unpublished schema23 changes still need integrated publication review;
no commit, deployment or live fund movement occurred this turn.

## Owner destination retention (2026-10-11)

Fixed a concrete configuration gap: validated ownerEcxXpub/ownerSolPubkey were
previously discarded by configure-file. Config now retains optional typed
OwnerFeeRecipients (public destinations only), validates both on loading, and
rejects unknown recipient fields. Missing/null legacy configuration stays disabled.
Configure-file preserves the original immutable record/retry behavior. This does
not enable automatic transfers yet or alter custody identity/saved withdrawals.

PASS: focused configure contract, session31425 exit0, including exact destination
retention, JSON round-trip, malformed xpub/public-key runtime rejection, legacy
absence and existing private-file/interruption tests. Separate read-only review
PASS for configuration scope. No services remain from this test. Receipt hashes
are in .audit/payout.tsv. No live funds/deployment/publication changed.

Next automatic-withdrawal implementation must:
- Resolve the configured owner xpub using the actual native node's descriptor
  implementation with an explicitly documented non-hardened receive path; do not
  invent keys, use a custody address, or add signing permission to the worker.
- Schedule from the existing worker critical cycle using a specific closed Store
  operation. Reuse withdrawal roots, journal entries, early fee holds, cohorts and
  the normal signing/settlement engine; add no endpoint, process or parallel wallet.
- Under the writer lock require active/fresh intake, sufficient settled Earned,
  threshold-sized bounded amount, no outstanding automatic withdrawal for that
  asset, and the same customer closing-capacity/fee/queue checks as manual admission.
  Reconcile threshold versus maxWithdrawal explicitly rather than queue an owner
  payment that can never complete its own threshold.
- Save recipient/amount/terms and deterministic journal identity atomically before
  any signing. Restart/configuration change must reuse existing saved terms, never
  redirect or duplicate work. Ordinary lack of earned funds/capacity skips the
  optional sweep without stopping customer settlement; malformed state fails closed.
- Test insufficient Earned, reserved-customer capital, fee/queue exhaustion,
  concurrent/repeated scheduling, restart, changed destinations, both assets and
  ordinary batch interval enforcement in the existing PostgreSQL contract.
Automatic sweeps remain a release FAIL until that full path is implemented/tested.

## Automatic earned-fee reservation (2026-10-11)

Scoped PASS: ReserveAutomaticFees is a closed Store write using active/fresh intake,
Earned-only funding, threshold<=cap, one live owner withdrawal per asset, and the
shared manual withdrawal capacity/commit helpers. Expected fee/inventory/queue
shortages return Nothing before mutation; malformed state fails closed. Saved
sequence/asset/destination determine identity. Existing pending work is never
redirected. Store 3801->3854 lines; no new schema table/process/API.

App/store build and full PostgreSQL payout/default/process/restore PASS59071 exit0;
source verifier PASS. Tests cover cap mismatch, no Wrapped Earned, 50 Native
reservation with early fee hold, repeated changed-destination refusal, paused
refusal, daily-fee shortage and unchanged financial/archive records. First fixture
run correctly required refreshed custody after reservation; fixed test, not guard.
PG cleaned. Hashes in .audit/payout.tsv. No live funds/deployment/publication.

Not yet wired to worker. Next: pass optional owner config into CustomerSettings
(Main.hs plus test constructors); derive/validate native public owner destination
using actual node descriptor methods (document path; add only those read methods
to worker allowlist); select eligible revenue before RPC; invoke the closed write
from existing worker critical cycle. A successful reservation invalidates custody:
do not immediately schedule another asset without reconciliation. Validate/configure
maxWithdrawal against automatic thresholds. Add worker/RPC/restart tests before
calling automatic owner payouts complete. Production remains FAIL.

## Automatic owner worker wiring (2026-10-11)

Supersedes the unwired status above. CustomerSettings carries optional recipients;
the worker schedules earned-fee reservations only when no payment candidates exist.
Native recipients use public network-checked wpkh(xpub/0/0), tpub for Signet, through
worker-only descriptor RPC permissions. Solana uses configured owner public key;
configuration rejects custody destination and caps below thresholds. Advisory
ReadAutomaticFeeAmount precedes RPC; locked ReserveAutomaticFees repeats authority
and ledger checks. Successful reservation ends the cycle for reconciliation.

Review found customer input-lock contention in the initial ordering: corrected
customer priority, then normalized only preview walletcreatefundedpsbt rpc_error_-6
to the expected funding-shortage code. Other method/error combinations retain
failure semantics. Separate reviewer scoped PASS. Full Cabal suite63972 exit0;
real PG payout/default/process/restore49387 exit0 covers the unchanged ledger
and worker priority before the final preview normalization. No need to repeat
unchanged PostgreSQL checks for that isolated RPC correction. Temporary PG cleaned.

Next acceptance: worker-level scheduling/restart on both assets, actual node public
derivation and funded owner path. Those remain unproven; no production completion,
fund moves, deployment or publication occurred. Refunds bypass threshold/interval;
normal swaps remain batched. Retain all other safety checks.

Restart follow-up: store build + PG payout/default/process/restore33933 exit0.
Both Native/Wrapped exact saved withdrawals survive reopened writers and changed
destination/cap/threshold/interval without duplicate records. Wrapped retains50
earned against new threshold20, so refusal is not an empty-balance false positive.
Cancellation restores all nonzero balances (new zero posting accounts are retained).
Separate source review PASS; PG cleaned. This tests durable reservation, not actual
worker signing/broadcast or later sealing under changed policy. Those gates remain.
Plugin discovery again confirms Codex Security not installed; prior installation
suggestion exists, no scan was run or historical upstream receipt reused.

## Optional Cloudflare ingress wiring (2026-10-11)

configure-file now retains private hosting.json and tunnel.token, with domain as
the public HTTPS origin only when a token is supplied. Token validation is bounded
ASCII; Nothing remains loopback-only. serverIp is inventory metadata, not binding
or DNS authority. External modular setup must create a remotely managed tunnel
whose hostname targets http://127.0.0.1:8080. No Cloudflare account API credential
is needed or inferred from the connector token.

build/install/tunnel pins official cloudflared2026.10.0 binaries by release digest,
publishes root-owned material atomically and uses DynamicUser+LoadCredential. The
installer invokes it only after start/readiness. It mirrors restore services.blocked;
verifies deployment/mint/owner through the supplied HTTPS hostname before enabling
boot startup. Failure/catchable interruption disables the service. Both loopback
and direct TLS now use the existing HTTP rate limiter, covering tunnel traffic.
Source service review found a crash gap, now addressed in source: verification
first disables/stops the persistent service, then uses a /run drop-in limiting
runtime to120seconds with Restart=no. Only after identity passes does the script
stop verification, remove the drop-in and enable/start the persistent service.
This ordering subsequently passed actual systemd interruption/reboot acceptance
with the scoped fixture described below.

Full Cabal/app+store/PG payout/default/process/restore93480 exit0. This is local
application acceptance, NOT execution of the Linux tunnel installer. No public
service, tunnel, live custody or deployment was started. Token-validation follow-up
has its own focused configure run. Remaining: Linux fresh/repeat/reboot/interruption,
actual hostname route, independent security review, existing release gates.

Final bounded-ASCII token configure contract81163 exit0; independent service source
review PASS after bounded-lifetime correction. Syntax/diff checks pass. Exact source
and log hashes in .audit/payout.tsv. Cloudflare parameter reference:
https://developers.cloudflare.com/tunnel/reference/run-parameters/#token-file


### Ubuntu tunnel component acceptance completed

Production build/install/tunnel ran unchanged on disposable Ubuntu24.04 ARM64
with real systemd, DynamicUser and LoadCredential. Fresh/repeat start, wrong-identity
refusal, restore blocking, SIGKILL followed by actual120second expiry/no restart,
rerun recovery, real reboot and restore-blocked reboot PASS. Permission, changed
credential and corrupt-binary refusals preserve installed material. Separate
read-only verifier PASS for this evidence. Lifecycle tests used an inert connector
and mocked HTTP, not a live Cloudflare route. The real pinned2026.10.0 ARM64 binary
separately matched its SHA and supported --token-file. Whole-host install and live
routing remain unverified. Evidence hashes are in .audit/payout.tsv.
The 1GiB/4GiB ecx-tunnel-check VM was stopped and deleted; no task VM remains.

Latest user confirmation: refunds bypass batching; normal swaps remain batched.
Existing two-chain PostgreSQL refund contracts cover below-threshold admission
inside the interval, unchanged round records, signing admission and invalid refund
round rejection. No policy change or repeated funded payment is needed.


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

### Published checkpoint verification (2026-10-11)

Commit b14cec4c94f0fb6cf6da1e7f07e68ea92f227ba6 is published on origin/main;
its tree matches the independently reviewed 4a376cd checkpoint. Full bridge-test
on that committed source PASS (session8673). Gitleaks8.30.1 scanned the current
directory and all27 local Git commits (non-shallow); each returned six flags:
two public dependency commit hashes, two Go dependency checksums, a disposable
provisioning-test token and the public xpub fixture. No scanner rules suppressed.
These results do not certify absence of secrets or replace the independent
security review, real-chain acceptance or Ubuntu whole-host installation.

Before a full clean-install VM, recheck disk: internal16GiB, CrucialX9 34MiB,
T705 2.5GiB available at this check. The documented default betanet snapshot alone
requires27GiB staging, excluding compiler/dependency/node runtime requirements.
Do not start that bootstrap with the current capacity or delete shared data.

### Owner scheduling liveness corrections (2026-10-11)

Separate source review found two P2s: active customer work could indefinitely
exclude owner scheduling on the other chain; native owner preview fee pressure
could pause all service. The worker now processes candidates then considers owner
work, skips Native while saved Native lock work exists, and prioritizes the asset
with the oldest immutable withdrawal sequence (never-used first). Only one new
reservation is committed per cycle. Optional native_fee_budget_exceeded defers
owner scheduling; ordinary signing/payment validation and integrity failures are
unchanged. No schema or runtime dispatch path was added.

Build78006, real PostgreSQL payout6917 and full bridge-test91453 PASS. New checks
cover priority before/after withdrawal, cancellation and reopened writers, and
fee-cap rejection without allocation/locking/signing/sending. Separate source
review PASS. Temporary database and test processes cleaned. These are not real
worker cross-chain progress, scheduler-error integration or funded acceptance;
extend the existing serve/HTTPS fixture harness next, without exporting dispatch.

### Canonical worker owner-reservation integration (2026-10-11)

The existing TLS contract now runs the real canonical-profile worker before its
signer phase. Explicit RPC fixtures provide consistent history and custody totals;
the observer and reconciler must certify them without fixture freshness overrides
while the worker runs. Native owner preview finds no available UTXOs and defers;
the worker reserves exactly one three-unit Wrapped withdrawal. After cancellation
and join, assertions require an unpaused ledger, unchanged Native allocations, an
unprepared payment, no attempts and no signing/broadcast calls. The existing real
HTTPS signer tests then consume that saved reservation. Devnet keeps its manual
reservation fixture. No production code or evaluator entry point was added.

A next-cycle RPC barrier prevents accidental preparation if the assertion thread
is delayed. Cancelling inside that guarded recovery can conservatively pause the
ledger; the post-join assertion detects this as failure rather than accepting it.
The fixture uses signature-specific transaction lookup and retains worker-created
history for later custody checks. Recovery waiting now requires the actual Solana
status request, not just a pause-event count.

Still unverified: scheduling while Native work is active, scheduler handling of
an actual preview fee-cap refusal, and funded owner transfers. Neither this
fixture nor its subsequent HTTPS signing phase certifies real-chain acceptance.

Final build and both Canonical/Devnet PostgreSQL+HTTPS contracts PASS (session54232
exit0). Temporary PostgreSQL and worker/signer/test processes were stopped and
removed. Exact source/log hashes are recorded in .audit/payout.tsv.

### Worker owner-preview fee-cap acceptance (2026-10-11)

The canonical worker fixture now supplies a validated Native preview with input100,
owner output3, change95 and fee2 against the saved cap1. Required decode/prevout
calls prove it reaches fee validation. The worker defers that optional withdrawal,
reserves Wrapped3 and remains unpaused, without address allocation, UTXO locking,
signing or broadcast. Build and both Canonical/Devnet PostgreSQL+HTTPS contracts
PASS (session48729 exit0); temporary PostgreSQL cleaned. Devnet still uses manual
reservation. This closes the scheduler fee-cap fixture gap above, not active-Native
work scheduling or funded acceptance. No production code changed. Refunds continue
to bypass batching; ordinary swaps retain their configured thresholds and interval.

### Active Native cross-chain worker acceptance (2026-10-11)

The focused TLS/PG case now seeds an already-backed-up Native broadcast through
the normal ledger operations. Synthetic RPC evidence consistently describes a
100-unit input, three-unit payment, 96-unit change and one-unit fee still in the
mempool. Custody is 2096 against the initial 2100 plus the pending debit of four.
The actual worker recovers, observes, reconciles and reuses its queue without
resending, then reserves exactly one Wrapped owner payout. Native balances and
the full saved broadcast attempt remain unchanged; the ledger stays unpaused.
No native preview, locking, signing or send occurs. No fixture
freshness/backup writes occur during worker execution; no signer is listening.

Build and focused PG process contract PASS (session28761 exit0), independently
reviewed. This closes the healthy active-Native scheduling fixture gap, not funded
transfers, real backup creation or repeated fairness. Test-only change: 58 lines
added and six removed in the existing test file; no production files or entry
points added. The active-only selector exits before the existing HTTPS signer
phase, which must still be run separately with both profiles.

Both full Canonical/Devnet PG+HTTPS contracts also PASS on this source
(session40286 exit0). Temporary PostgreSQL and process-test services cleaned.

### Consolidated current-source local acceptance (2026-10-11)

All 17 documented PostgreSQL modes have passing receipts on application source
3113658: 14 modes in session70742 exit0, plus the three TLS modes from sessions
28761/40286. The macOS harness adapts toolchain/build paths and the SDK suffix;
this is not Ubuntu installation acceptance. The updated recipe clears all mode
selectors and includes payout, complete-resume, cohort-residue and active-Native
cases. Its schema reference is corrected from22 to23.

The 1001-history case completed full refund/settlement/replay sequences, real
encrypted restic restore and financial comparisons. Mean customer ReadOrder over
ten reads was about18ms at one refund,28ms at100 and220ms at1001 on this host.
These are local timings, not a concurrent production capacity guarantee. The
separate history-progress case passed restart, stale CAS, rollback, contiguous
checkpoint and duplicate-posting refusal. All14 harness modes returned exit0.
The disposable PostgreSQL cluster and retained synthetic history backup were
removed after shutdown; logs remain in the receipt's temporary evidence directory.
No application change, live funds, public ingress or production gate waiver.

### Security review and private test log (2026-10-11)

Codex Security scan dd391a4d-041c-4fb7-a16e-12378cb8f1ad completed against
1c8da93 with confirmed Native-history nonprogress (Medium) and temporary test-log
symlink truncation (Low). This is not a production security pass. Native scanning
still needs a complete bounded enumeration design; raising limits or advancing
coverage past unprocessed receipts is not a fix. Spool-race and dependency review
uncertainties remain open.

Corrected both server test-log references to use the private directory. The
existing process contract now plants the old sibling symlink and verifies its
sentinel remains intact and the private log is regular. One-job build and both
server/server_canonical PostgreSQL contracts PASS (session20803 exit0); fresh
read-only patch reviewer PASS, static scope only. Disposable PostgreSQL stopped
and its data removed. No runtime or financial behavior changed. Refunds bypass
batching; ordinary swaps retain configured thresholds and intervals.

### Pinned Native RPC repair investigation (2026-10-11)

Verified actual ecash-com/bitcoin ca64033c1374 transactions.cpp, not generic
Bitcoin documentation. listsinceblock has no pagination; target_confirmations
only selects lastblock. listtransactions count/skip is not a stable cursor:
conflicted receive entries disappear from its row set. Do not implement offset
pagination or advance coverage past a truncated response.

gettransaction also omits conflicted receive details (ListTransactions minimum
depth0). Our negative-confirmation fixture retains them, so it does not prove
real conflict handling. CommitScan only updates supplied deposits: the repair
must explicitly invalidate saved receipts for a negatively confirmed transaction,
preserving bindings/accounting and source-loss review. Existing payout rechecks
are separate protections; this inspection does not establish a funds-loss exploit.

Read-only investigator confirms whole-response streaming into sealed scratch can
remove application aggregate caps while preserving coherent capture. It cannot
resume a truncated HTTP response, reduce daemon memory, recover pruned detached
blocks, or certify stale custody as fresh. Required repair spans capture, paged
receipts/evidence, recovery selection, treasury proof lookup and custody overlap;
the existing60-second freshness guard remains. Production fix is still open.
Retained pinned-source SHA256:
5b635c860e448452518bef165c2571474daff9a5991528423d60cffb2343c01a.
Investigation: Codex Security standalone findings/native-history-pinned-rpc-investigation.md.
No services started, funds moved, limits raised or runtime changes made.

### Native empty-detail conflict repair (2026-10-11)

The real-ledger regression failed before the patch (session98057 exit1 at the
saved eligibility assertion). CommitScan now invalidates all saved Native
outpoints for an identity-matched negative transaction event, in128-row keyset
pages inside its existing transaction. Immutable receipt fields and balances are
preserved; observeDeposit retains normal source suspension/review behavior.
Reference event role is derived from retained receipts without fabricating RPC
details. The normalized evidence remains usable by independent source inspection.

Source inspection permits absent matching details only for negative status,
binding the saved outpoint to decoded amount/script, wallet ownership and saved
instruction. Matching scanner status, synchronized wallet view, mempool absence,
spent output and identical second transaction read remain mandatory before loss
classification. Positive/shallow sources still require their ordinary details.

Build plus default PostgreSQL contract PASS (session73768 exit0), covering130
outpoints, unrelated-transaction isolation, malformed identity, late-error rollback,
source-review replay and unchanged accounting. Full Cabal bridge-test PASS
(session87967 exit0), including empty-details loss inspection and refusal controls.
Both disposable PostgreSQL clusters stopped and removed; no live funds moved.
The large-history finding and real-node conflict acceptance remain open.
Fresh native_conflict_patch_reviewer: PASS, static four-file scope; no actionable
bypass/regression found. Scanner-to-ledger-to-inspection combined fixture and
real-node conflict execution are not established by these separate contracts.

### Backup spool privilege boundary (2026-10-11)

Resolved the scan's GNU-install uncertainty in a disposable Ubuntu24.04.4 ARM64
VM (1CPU/1GiB RAM, no host mounts). With coreutils9.4, a symlink substituted after
the precheck made the old root install-d command change a root-owned target to
ecxnode ownership. The script now runs spool creation as ecxnode:ecxnode using
runuser, before traversing the mutable path. The same substitution cannot mutate
the protected target; fresh and repeated normal creation preserve0700 and content.
Shell syntax and deterministic Linux before/after contract PASS; fresh separate
backup_spool_patch_reviewer PASS for source scope. No Haskell code changed.

The VM was stopped/deleted. Evidence is retained through Codex Security as
artifacts/spool-permission-check.sh and .log (logSHA256
ac58f0c4b644202a7d5b263bf2f68e147dba73517a297dac2812a16cb8329600).
This closes the backup helper's root path-following issue, not node-originated
denial of service or whole-host x86_64 installation acceptance. Other managed-node
root filesystem operations still warrant separate review. Public access stays off.

### Native capture feasibility (2026-10-11)

Existing pinned Aeson2.3.2 token parsing handles streamed history without a new
dependency or custom JSON lexer. The corrected probe inspected one million IDs:
exit0,6MiB GHC memory,18,956,288-byte peak process RSS,1.55s wall time. A separate
actual localhost HTTP capture/replay probe passed a100,000-row response above4MiB.
Late RPC errors, truncated/trailing JSON, HTTP500 and timeout released no rows;
all captures were removed. Validation/replay use duplicates of the same open
descriptor, never reopen its pathname. Fixture server/client exited. These are
protocol feasibility tests, not live-chain acceptance or a production fix.

Retained through Codex Security: artifacts/NativeHistoryProbe.hs and
native-history-probe.log; artifacts/NativeCaptureProbe.hs and
native-capture-probe.log; findings/native-capture-integration-evidence.md.
Read-only native_capture_integration investigation confirms schema23 can hold
the needed checkpoint scratch and receipt-specific evidence without DDL. Do not
reuse CommitScan unchanged for partial pages: it advances coverage and clears
failure. Keep the real cursor and incomplete health until the full captured
response and recovery sweep are processed; never reuse offsets against a new
response or refresh the original observation timestamp to pass freshness.

Integration remains open: large individual transaction parsing, per-receipt proof
binding/treasury verification, atomic partial-page commits, keyset source recovery,
and streamed custody overlap with its existing60s deadline. No production code,
schema, funds or public access changed. Native-history finding remains open.

### Streamed Native custody history integrated (2026-10-11)

Custody reconciliation now uses the fixed listsinceblock streaming reader rather
than ordinary bounded RPC and its 1,000-entry list. NativeHistory privately
captures to an immediately unlinked file, validates the complete response, then
replays from the same descriptor. Its local-only manager avoids the general
HTTPS response-buffer hook. Existing Native endpoint/cookie validation is shared;
ordinary RPC limits and signing/DSL authority are unchanged. Consumers are never
retried. Each entry receives the validated capture anchor before inspection.

Fresh native_stream_patch_review identified two candidate regressions: advanced
anchors lost refusal precedence, and result:null hid following RPC errors. Both
were corrected with explicit regressions. Final Cabal bridge-test and default
PostgreSQL contract PASS (session73835 exit0), including >4MiB transport, 2,001
custody entries, a final-entry mismatch, advanced-anchor precedence, null-result
errors in both field orders, error retries without duplicate consumption, and
existing balance/revision/60s freshness checks. Review was not a whole-finding
PASS; the final corrections were verified by parent source review and tests.

One private 130-line module; net +140 production Haskell lines and +88 test lines.
No new runtime dependency, schema or configuration field. Final logs retained via
Codex Security: artifacts/native-stream-reviewed-suite.log and
native-stream-reviewed-pg.log. PostgreSQL stopped and disposable data removed.
Remaining: observer capture/page commits, large individual transactions and
receipt evidence, source recovery paging, full live-chain/security acceptance.
Disk capacity and per-entry size still bound feasible captures; this is not an
arbitrary-history liveness guarantee. Public access remains off.

### Native observer pages and recovery enumeration (2026-10-11)

Observer now consumes the validated Native history capture incrementally. The
closed CommitNativePage saves receipts/evidence and unhealthy scan status in one
transaction, without advancing coverage or changing the operator pause state.
Only complete history replay plus the recovery-source sweep returns the empty
final CommitScan. Original scan time, cursor/origin checks, review pauses and
idempotent financial postings remain. Both observer and source recovery enumerate
128-row deposit-ID keyset pages rather than failing above 1,000 candidates.

Fresh native_pages_patch_review returned FAIL on a lazy recovery-error accumulator
which retained prior successful pages. Parent confirmed and forced it before
recursion. The focused GHC -O1 reproducer grew from 5,255,672 to 41,305,528 bytes
maximum residency for the old 2,000/16,000-page loops; the corrected loop stayed at
44,328 bytes, with identical first-error and complete-traversal results. This is
an accumulator reproduction, not a whole-worker memory benchmark. No second
independent PASS is claimed.

Final Cabal bridge-test and full default PostgreSQL contract PASS after that fix
(session32410 exit0). Coverage includes 1,101 transactions/recovery sources,
partial-page replay/rollback, stale cursor/origin rejection, unhealthy readiness,
unchanged normal pause state, and pending/removing candidates across keyset pages.
The initial bulk fixture crowded the separate bounded treasury listing; it was
moved after that contract without weakening either assertion. Retained final
evidence: Codex Security artifacts/native-pages-reviewed-suite.log,
native-pages-reviewed-pg.log and native-pages-heap-*.log. Net +26 production lines
across four existing modules, +85 test lines across two existing files; no new
module, dependency, schema, configuration or signer route.

Next: large individual gettransaction responses/output lists and receipt evidence
still have independent caps. Complete their bounded representation and verify
treasury/source/custody consumers before closing native-history-nonprogress.
Long-scan freshness, actual node conflict acceptance and the remaining release
gates are still open. No funds or deployment were changed; public access stays off.
