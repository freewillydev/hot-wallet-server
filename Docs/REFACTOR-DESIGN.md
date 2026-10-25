# Six-area refactor design review

**Design only, 2026-10-25. No implementation, build, test, database, service,
provider, deployment or financial operation was performed for this review.**

The deeper review supports a clearer version of the existing architecture,
with approximately unchanged total source size. It does **not** support cutting this complete
product to 7,000 or 4,000 lines without further architectural or scope changes.
Most proposed savings are small after counting replacement types, shared helpers,
comments, regression checks and module registration. Several useful improvements
add lines. Treat the estimates below as planning budgets, not promised results.

## Scope and evidence

This develops the six next steps from the architecture map: coherent DSL baseline;
configuration; installation/update/recovery; Store/Opaleye; critical workflows;
SQL and test plumbing. The underlying full-source inventory is
[CODE-MAP.md](CODE-MAP.md) and [architecture-lines.tsv](.audit/architecture-lines.tsv).
This deeper pass reread the relevant production modules and selected test
scenarios, with three read-only specialist reviews. The later Grok/Claude reconciliation below
adds two read-only source checks; the DeepSeek reconciliation adds two more targeted
read-only checks. It is not a second exhaustive
read of every dependency, historical document or unrelated file.

Repository baseline is `dbff7c6ba1579b51ea60fb1cb3bedb7d2317bb2e`, whose application
source matches the earlier mapped base `a485cac557a63395ebb6ef294836e9b9113ff707`,
plus the preserved local `Operation/Internal.hs` draft. That file has 459 lines
and SHA-256 `32d6f2fe05b1fbd98a5de056f0444adc9e37aa6c414e60ec2879c2f3aca1669f`.
It has not been reset or edited. The untracked Claude `ARCHITECTURE-MAP.md` and Grok Build
`CURRENT-ARCHITECTURE-MAP.md` were subsequently read as evidence; their source files
remain untouched and outside this publication. Reconciliation starts from docs-only
commit `b30cbc342581b05a178ca25b7bdfee1266c08541`; application hashes are unchanged.
The original snapshot manifest hash is
`d1fc9f7d2077bc16ff507d5328dbb18bc7ebeb387bd5f620d983d8737a29cc14`.

All counts below are physical lines, including comments/blanks. The baseline has
116 authored code/test/build/config files and 37,510 lines. Documentation,
generated outputs, data fixtures, lockfiles and third-party sources retain their
existing inventory categories; moving something into one of those categories
does not earn a saving. The Rust file still includes its 294 inline test lines
in the original runtime bucket. No formatting compression is budgeted.

[refactor-estimates.tsv](.audit/refactor-estimates.tsv) contains a disjoint row
for every one of the 116 existing authored files plus the three proposed files,
with before hashes and three target budgets. Unchanged files remain in the total.
Each shared helper is charged once at its destination. Proposed counts are not
statistical confidence intervals; exact sums make the accounting inspectable,
not the forecast certain. A sensible verbal estimate is **about 37.7k lines,
with a planning range of 37.0k–38.7k**. This is the bounded six-area plan plus
the verification runner; broader configuration/Store redesigns remain uncosted.

## Before and proposed after

| Area / scoped footprint | Files before → after | Before | Optimistic after | Central after | Conservative after | Central change |
|---|---:|---:|---:|---:|---:|---:|
| 1. Reconcile operation grammar | 1 → 1 | 459 | 510 | 510 | 510 | +51 |
| 2. Typed configuration projections | 5 → 5 | 1,919 | 1,869 | 1,929 | 2,036 | +10 |
| 3. Setup/update/recovery mechanics | 9 → 9 | 2,123 | 2,115 | 2,165 | 2,273 | +42 |
| 4. Store, projections and evidence | 3 → 4 | 4,534 | 4,485 | 4,589 | 4,720 | +55 |
| 5. Critical evaluator clarity | 1 → 1 | 1,260 | 1,266 | 1,277 | 1,300 | +17 |
| 6a. Schema, existing update contract | 1 → 1 | 936 | 936 | 936 | 936 | 0 |
| 6b. Tests/formal, assertions retained | 14 → 15 | 13,056 | 12,494 | 12,934 | 13,504 | −122 |
| 6c. One-command database verification | 0 → 1 | 0 | 100 | 120 | 160 | +120 |
| Cabal registration, new helpers paid | 1 → 1 | 111 | 115 | 115 | 115 | +4 |
| Unchanged remainder | 81 → 81 | 13,112 | 13,112 | 13,112 | 13,112 | 0 |
| **Whole authored scope** | **116 → 119** | **37,510** | **37,002** | **37,687** | **38,666** | **+177** |

The revised central forecast adds **177 lines**: 122 fewer in the test/formal
bucket and 299 more elsewhere, including a 120-line verification script. The
previous +30 forecast rises by 27 for named critical resources and 120 for the
runner; those costs must not disappear from a reduction claim. Optimistic reduction
is 508; the conservative design adds 1,156. New files are a private pure evidence
decoder, test-only helpers and one development verification script. There is no
new application service or Haskell executable. File splitting alone saves nothing.

SQL offers a separately measured **approximately 229-line** reduction, from
936 to 707. It changes the exact schema hash used by install, retry, archive and
upgrade checks. It is excluded above because a compatible rollout is unresolved.
Subtracting it gives a source-only central number of 37,458, **before any unknown
compatibility-policy implementation cost**. That is not a shippable forecast.
No migration, reset or weakened hash check is implicitly included.

Existing source groups and duplicate bodies can be measured now; replacement
lengths cannot. Even the detailed old/new block budgets below are forecasts,
not verified deletion plans. The test harness has the broadest uncertainty.
A more extensive redesign might save more, but this audit has not established
one that preserves this whole product and its safeguards. Do not extrapolate
these numbers into a promised 7k target.

## What improves, and what must remain

| Area | Proposed shape / what becomes easier to understand | Behavior and safeguards to preserve | Design risk / verification needed later |
|---|---|---|---|
| 1 | One complete eleven-workflow grammar, with every consumer agreeing. A reader can follow an operation from existential to post-Refl Flow to evaluator. | Caller/severity/result identity; closed capabilities; private internal steps; unique signer result families; retry, cancellation and owner work; one runtime critical dispatch. | The current draft is statically inconsistent. Coherent positive compilation must precede negative type checks. Restoring missing functionality costs lines. |
| 2 | One validated operator input and typed projection; explicit runtime, role, public and hosting outputs. Updates apply a closed set of field edits. | Original secret bytes, legacy syntax, supplied-key import, interactive-only key generation, runtime role separation, saved quotes, immutable identities and staged replay evidence. | Typed defaults may be longer; decode/reencode can alter legacy fields or seals. Compare exact representations as well as values. |
| 3 | Small fixed-purpose file/service helpers, with each lifecycle procedure still visibly ordered. | Distinct ordinary-update and backup-switch checkpoints; stopped signer and fence checks; immutable journals; secure old-wallet archives; unknown-outcome restore refusal; reboot interlocks. | Do not merge protocols just because their subprocess/file calls resemble each other. Real systemd and interruption acceptance remains necessary. |
| 4 | Table mappings declared once; named pure selections; local load → decision → explicit writes; small typed views over saved evidence. | Closed Opaleye operations; separate reader/writer roles; transactions, all locks/fences; integer accounting; exact hashes/bytes; full liabilities; independent signer rereads. | Typed records cost lines. Query scoping and error precedence must be compared before calling them equivalent. Keep evidence records from becoming authority tokens. |
| 5 | Keep existing F.do design; name private environment fields, optionally make constructor cases visible and share one exact paused-state check. | Entire continuation inside gate/scope; exception/cancellation semantics; fresh pause reads; asymmetric replay order; no nested gate acquisition or extra signer path. | Named resources cost more lines than the small helper savings. Retain current form if the replacement adds harder type machinery or makes authority less visible. |
| 6 | Test plumbing shared narrowly; independent arrangements/expectations explicit. Identical SQL bodies may be considered separately. | All refusal cases, shrinkers, financial snapshots, concurrent sessions, failure prefixes, negative type cases, TLA model and all 106 SQL trigger attachments. | Smaller tests are not fewer assertions. SQL compatibility is unresolved. Do not declare an expected compile failure a success if the whole baseline is broken. |

The runtime architecture remains: Servant handlers construct typed existential
operations; `interpret` checks exact types and constructs deferred Flow after
`Refl`; safe/critical evaluators run concrete effects. Worker and signer remain
separate processes with separate permissions. Critical dispatch remains the
single runtime entrance for signing requests; root lifecycle and ATA setup remain
separate, explicitly privileged boundaries. The HTTP response contains ordinary
typed JSON, not a serialized dictionary. Flow is a sequence, not a cross-chain
transaction or rollback mechanism. The TLA+ model constrains modeled paths; it
does not prove all Haskell/IO behavior. Preserve the source-to-model correspondence
checks and the assumptions behind that model.

Configuration update detail: `Reconfigure.configurationFiles` currently overlays
selected keys onto the original Aeson value. The proposed typed projection must
produce **closed authorized field edits applied to that original value**. Do not
decode an old Config and generically reencode it: that could normalize legacy
`minInput`/`maxInput`, absent/null optionals, unmodified fields or seal bytes.
Fresh configuration may encode a newly constructed record. Replay compares the
same immutable original/staged bytes. Golden checks must cover these differences.

## Grok Build and Claude conclusions reconciled (2026-10-25)

The requested Grok Build CLI chat is **“Hot-wallet ECX SOL wrapper architecture
audit”**, session `01a17359-0559-7673-b09e-57c3480c62ef`. Its final conclusion
(14:26:07 UTC) identifies `CURRENT-ARCHITECTURE-MAP.md` and explicitly reports no
builds/tests. The matching Claude Code audit is session
`9f7e1f04-3046-4dc3-a298-e0ed545068a4`; its final substantive conclusion at
14:12:28 UTC identifies `ARCHITECTURE-MAP.md`. Claude's saved title is absent;
its original request, repository and named output establish the match. The
local transcript locations and artifact hashes are recorded in the audit receipt;
private full chat logs are not copied into Git.

Both maps describe committed application source plus a separately identified
inconsistent local grammar. Our inventory counts that local draft. Claude's actual
compiler logs show **lib:workflow only** failing on the draft and passing on an
archived HEAD copy. That strengthens the baseline diagnosis; it is not a full
executable build, a test-suite pass or new execution by this review.

| Conclusion | Revised decision and source-grounded limit |
|---|---|
| Coherent baseline and feature branch first | Preserve the draft; reconcile all eleven workflows before cuts. Pin main and `codex/sidechain-fast-withdrawals` separately: the latter is at `1ede7fb3541fa4aed34b29d97ab89e54abf187a3`. Main's four-route wrapper does not contain those sidechain features. No silent merge or claim that one map covers both. |
| Database checks should be automatic before refactoring | **Adopt and move earlier.** The previous LOCAL-DEVELOPMENT recipe had seventeen modes but omitted `ECX_GAS_TOP_UP_ONLY` from both matrix and reset. Its early exit at StoreCheck:110–111 could mask other modes. Correct the recipe now; plan eighteen explicit modes plus the separate provisioning contract, with isolated state and source-bound receipts. |
| One canonical settings model | **Adopt semantic ownership; design the physical consolidation before promising cuts.** Reconfigure:142–168 orders backup probes, service stops, publication and target backup; 246–284 emits different role/public/secret/seal artifacts. They are not nineteen interchangeable copies. Preserve those boundaries and replay, even if later generated projections reduce files. |
| Make Critical readable | **Adopt named private resources.** Keep the existing post-Refl Flow. Direct calls require proof that `checkedOperation`, observation-only restrictions and all continuation failure scopes (Critical:396–414,482–506) survive. They are not blanket-authorized bypasses. Retain one runtime critical dispatch and no exported signer/connection selectors. |
| One table mapping and typed evidence | **Adopt the bounded Store design.** Each evalRead already opens a read-only RepeatableRead transaction (Store:327–332). Combine facts only within a specified closed operation; no snapshot spans RPC/backup or replaces the signer's fresh before/after reads. The proposed 800–1,200-line saving has no paid replacement design yet. |
| One home for each financial rule | **Adopt an ownership map.** Lifecycle owns pure decisions, Store supplies locked facts and commits, signer independently validates authorization, SQL guards persisted integrity. Similar checks across those boundaries are not redundant. Centralize formulas/policy representation; retain independent enforcement and expected-result oracles. |
| Consolidate SQL triggers | Keep the measured conditional ~229-line opportunity. There are **98 function definitions and 106 triggers**, not ~194 functions. Exact schema hashes govern install/upgrade/restore; a passing dump restore alone cannot authorize changed schema bytes. |
| Delete dead and legacy paths | First prove call/export/persisted-state reachability. New orders reject memo owners, but PaymentSource:57–70, SolanaObservation:75–84 and Store:2810–2819 still process saved memo bindings/refunds. `hints`, old key syntax and setup transitions also have consumers. Schema 23 alone does not make those states obsolete. |
| Cut optional features/toolchains | Treat as separate product proposals. Cohorts, refunds/retries, source-loss cover, fee sweeps, wallet rotation, public status, interactive setup and test profiles have requested behavior. Plain JS conflicts with the Haskell-JS instruction; Rust currently fits the permitted FFI exception. Moving source builds off a production host does not remove repository lines. |
| Full-RBF compatibility is uncertain | Record a focused acceptance question: NativePayment:75,163,504–508 preserves non-BIP125-signalling sequences. Verify the pinned ECX node's replacement policy later. Static source does not establish that replacement works or fails on a running node. Preserve pending families meanwhile. |

**Correct scope comparisons:** runtime/setup source is 21,725 lines including
294 Rust inline test lines; excluding those tests gives 21,431, explaining the
other maps' “about 21.4k.” Whole authored source/test/build/config is 37,510.
The 95 mentions of CriticalEnvironment occur on 94 lines; that is not 94
constructor matches. The source has 21 operator commands. Larger savings quoted
by the other audits overlap features/modules and are hypotheses, not additive
reductions from our disjoint budget.

Claude also found two unimplemented notes in the original Main.hs sketch:
**weekly unwrapping limited to 10% of supply** and **multisig coordination**.
Record them as unresolved historical requirements. A supply definition, rolling
window/reorg rules and signer quorum/recovery protocol would need specification;
they are not silently added to this simplification. The later explicit approvals
for a hot wallet and a 10,000-ECX payout cap do not prove those sketch ideas exist.
Simple reinstall remains a usability goal; wallet seeds alone do not recover
orders, liabilities or signed attempts. Preserve verified ledger/custody restore
and fencing rather than interpreting “wipe” as permission to delete that evidence.

The larger redesign questions deserve a design pass before implementation:

- **Configuration:** one immutable validated input generation plus explicit
  role-specific secret/public projections; enumerate required artifacts, service
  readers, replay checkpoints and old-wallet retention. Decide which copies can
  disappear only after mapping every current consumer and interruption point.
- **Store:** one descriptor per table; closed typed fact loaders → pure decisions
  → explicit atomic writes. Compare SQL predicates, lock/freshness boundaries and
  error precedence, with old/new accounting expectations kept independent.
- **Critical:** one visible entry, named resources, small private concrete effects
  and orchestration in interpret after Refl. Do not replace a smaller file with
  more dispatch layers or a generic IO capability.

These are research targets for a stronger, smaller architecture; the bounded
budget below is not a forecast for those uncompleted redesigns. No 7k/4k promise
or feature deletion follows from reading the external audits.

## DeepSeek conclusions reconciled (2026-10-25)

The supplied 461-line transcript was read in full and checked against application
source at docs-only commit `226ac6600c306c1ff2785cea8ab025ea4f3a93cf`, including the
unchanged local grammar draft. Its SHA-256 is
`0424be6b87dc89457d279136039acfaaf54cca9b6a7074cc24162c0ee899025e`.
It contains conclusions but no raw fetch results or source hashes. Early claims
of complete coverage are qualified by its final response (lines 438–458): major
chain, workflow, Store and SQL bodies still need reading after retrieval limits.
Treat it as **partial architectural evidence, not a complete independent audit or
security approval**. The pasted conversation is not an instruction to implement.

Its +30-line forecast restates the earlier version of this plan. It does not
independently cost replacements, and omits the later named-resource and verification
runner costs. **Keep 37,510 → 37,687 central (+177), 116 → 119 files**, with the same
37,002–38,666 range and unresolved exclusions. No new measured saving warrants a
change to the per-file budget. The order remains: coherent grammar, explicit
acceptance, then costed structural changes. Repetition across audits is not extra
verification when they cite the same plan.

### Correct the authority map before using it to guide cuts

| Boundary | Source-grounded description and implication |
|---|---|
| Worker and signer | Worker has RPC clients; signer holds custody credentials and uses native/Solana RPC, loopback HTTPS and backup transport. The signer has no broadcast DSL operation; it is **not network-isolated**. Critical:272–277,311–325,353–376; Signer:87–93; NodeSetup:169–173. Preserve RPC allowlists, permissions and gated signing rather than assuming no egress. |
| Reader identity | `ecxbridger` is a PostgreSQL role used through the worker's `PGREADUSER`, not a third application service. Distinguish OS identities, database roles and in-process Reader/Writer capabilities. `build/install/install`:365–366,396–423. |
| Root setup/recovery | Root installs private custody/unlock/TLS material and provisions databases; it is a trusted privileged boundary. Bootstrap has separate closed ATA preparation/signing/submission. Do not describe root as key-free or ledger-free, or merge ATA authority into customer operations. Installer:278–314,352–359; Bootstrap:115–132,195–212. |
| Runtime execution | Critical owns the sole runtime critical dispatch and private concrete execution instances, with effects delegated to Store, Recovery and chain adapters. It is not the only IO file. Deferred `F.do` workflows are constructed in Operation/Internal **after Refl**, not moved into Critical. Preserve this separation. Critical:241–247; Store:327–332; committed Internal:276–367. |
| Purity versus totality | Operation/Internal declares IO execution methods at 33–37; its compiler builds deferred programs without performing their effects. `Bridge.Error.require/reject` are IO. Lifecycle is pure but contains a partial eliminator at 113; the failure is unreachable for `amount 0` under Domain:28–30. This is no proof of totality and no demonstrated reachable failure. Removing that partial expression is an optional clarity change to cost separately. |

### Refactor proposals: adopt only the supported scope

| Proposal | Decision, actual size and preserved contract |
|---|---|
| Replace a claimed ~600-line configuration parser | **Defer.** All of InstallConfig is 279 lines; `parseInstallRecord` and local helpers are 108–188, **81 lines** (85 including introductory comments). It already uses `lex`/`Read`. No parser-library reduction is demonstrated. Preserve nested comments, string gaps/escapes, field reordering/defaults, old-record-only base58 compatibility, duplicate/unknown/missing/delimiter refusal, integer bounds, secret-free line diagnostics and original stored bytes. ConfigureCheck:321–360,378–432,473–478 provides existing coverage. |
| Merge publication and rotation journals | **Reject protocol unification; retain narrow shared mechanics.** RotationFiles already imports ReconfigureFiles.savePrivateRecord. Reconfigure saves old/new byte snapshots and hashes; rotation records directory device/inode/owner/group/mode and archives without overwrite. Their parent/ancestor ownership policies differ. Preserve separate journals, replay states, link checks, fsync ordering, locks, service states and checkpoints. ReconfigureFiles:52–166,260–276; RotationFiles:7,26–109,159–227. The existing +42 lifecycle forecast already pays for helper replacements. |
| Share configuration fingerprint normalization | **Keep the existing two-caller scope.** Configure:685–690 and Reconfigure:311–319 share five role-path normalizations; Reconfigure also checks completed setup. Upgrade:98–105 checks saved hashes/fingerprints and does not duplicate that block. Do not budget three deletions. |
| Remove repeated Opaleye mappings | **Keep descriptor-derived read projections, not blanket alias removal.** Schema has 65 `O.table` occurrences for 49 distinct relation names, 13 names repeated. These include views. `paymentRoots` names physical `intents`; `withdrawals` names `fee_withdrawals`. `sourceApprovals` already derives a selection. `nativeRecoveryDetails` reads a view selecting qualifying settled recoveries, whereas `nativeRecoveryRows` reads its base table. Preserve that predicate, read-only surfaces, tuple/hash order and the separate writable custody projection. Schema:66–88,254–261,290–294,324–329; schema.sql:290. Existing narrow projection budget is ~14 lines saved, not a fresh additional saving. |
| Name repeated size limits | **Adopt as a separately costed readability candidate.** Equal numbers cover different units and boundaries: path characters (InstallConfig:266–269), manifest bytes (ReconfigureFiles:66), 4096/8192-byte SDK inputs/output (SolanaHelper:137–149; Rust:253–255), 4096-byte signer requests and 524288-byte responses (Signer:85; Critical:419–445). Name limits where owned; keep stricter per-reader limits and Haskell/Rust ABI agreement. No generic global maximum, widening or new savings claim. |

Two low-level claims are confirmed, with narrower assurance: the C shim is
**37 lines**, and performs context randomization before secret scalar work
(native_key.c:10–20; NativeKey:20–35). Rust/Haskell buffer bounds and the 1232-byte
Solana wire limit exist; they do not prove arbitrary FFI pointers safe or establish
an exhaustive cryptographic review. SQL has **six deferred payment constraint
triggers and two deferred payout constraint triggers**, eight such triggers total.
Deferred foreign keys are additional constraints. Retain every attachment, not only
the six mentioned in the audit. These corrections clarify the map; they neither
change application behavior nor satisfy outstanding build/security/release gates.

## Recommended implementation order, when implementation is requested

1. **Pin the product and source baseline.** Keep main's wrapper and the sidechain
   branch inventory distinct. Intentionally reconcile the preserved grammar with
   all eleven workflows. Establish positive compilation of the actual tree before
   using negative type checks; no committed-file overlay may stand in for it.
2. **Make the financial acceptance batch explicit before structural cuts.** Freeze
   the scenario/assertion inventory and implement the single-command disposable
   runner described below. Run every selected mode with selectors cleared, a fresh
   database and a labelled receipt. Keep production worker/signing/broadcast
   acceptance distinct from pure Flow traces and direct Store contracts.
3. **Specify the larger configuration/Store alternatives before spending on tiny
   helpers.** Map consumers, authority, persisted bytes and failure points; budget
   every removed block and replacement. Choose the stronger coherent option. The
   costed small changes below are a fallback, not evidence that all larger cuts
   are impossible or already designed.
4. **Implement one configuration/lifecycle slice together.** Use validated typed
   projections; preserve original JSON overlays, role boundaries, key import and
   service/backup ordering. Share fixed-purpose mechanics only. Keep distinct
   backup-switch, wallet-rotation and restore protocols visible.
5. **Consolidate Store representation and then Critical readability.** Derive
   selections from descriptors; use narrow typed evidence/facts. Introduce named
   CriticalEnvironment fields and keep all authorizations/scopes. Prove a proposed
   direct-leaf change separately before removing any grammar traversal.
6. **Prove each dead-code deletion; keep policy choices separate.** Search actual
   callers, exports, tests, saved rows and restore formats at the selected commit.
   Preserve historical memo handling until its obligations are accounted for.
   Keep SQL consolidation conditional on an explicit exact-hash compatibility plan.
7. **Batch expensive verification by coherent slice.** One component build and
   affected focused checks, then the complete matrix after interacting changes
   settle. One build job and one task-owned cluster at a time; no live/funded modes
   in the default runner. Re-run for demonstrated failures or changed source.
8. **Measure and independently review the actual result.** Publish physical and
   nonblank counts, moved code, introduced helpers, assertions and failure-order
   changes. Passing design review does not certify implementation or production.
   Keep backups and deployment review separate.

This ordering reduces repeated integration work; it cannot guarantee bug-free
implementation. The highest-value first changes are coherent baseline and
explicit financial acceptance and configuration/lifecycle clarity. The largest
definite duplicate body is SQL,
whose deployment constraints currently outweigh the line-count benefit.

## Build, tests and independent review

| Evidence | Status for this proposal |
|---|---|
| Current source counts/hashes and disjoint estimate arithmetic | Static inspection; audit receipt records final comparison |
| Proposed code compiled | **NOT RUN / code not written** |
| Behavioral regression, negative type checks, PostgreSQL/TLS, TLA execution | **NOT RUN** |
| Fresh Ubuntu install/update, real network/funded recovery | **NOT RUN** |
| Separate design reviewer | Verdict and immutable artifact hashes in `.audit/refactor-design.tsv` once reviewed |
| Security or production certification | **Not established or changed by this design review** |

Historical results in DONE/RESUME keep their original source and scope. In
particular, tests using the committed Operation overlay do not validate the
current dirty draft or these proposed replacements. The future coherent build
starts with the documented Cabal entry points, GHC 9.14.1 and `-j1`; default
`bridge-test` is not a substitute for its separate database modes or negative
CPP compilation cases. Detailed required checks appear in the following design
sections. A design reviewer can judge feasibility and preservation obligations;
only implemented and executed evidence can establish build/test success.

## Detailed design records

The following source-span analysis includes all proposed replacement costs and
the reasons to retain apparently repetitive code. Source paths are relative to
this repository. Line references refer to the frozen baseline, not future files.

# A. Detailed operation grammar and critical workflow design

## Conclusion and ownership

The target is the existing small closed authority architecture with one coherent eleven-workflow grammar. Reconciliation costs 51 production lines before any simplification. Critical already contains most of the desired separation; its two local cleanup candidates save only 0–14 lines, centrally 10. Named private resources add a separately paid 20–40 lines, centrally 27. Across these two files the revised result is therefore a **57–91-line increase**, centrally 68. This is a prerequisite and auditability improvement, not a source of large line reductions.

These budget rows own exactly two existing files:

| Area | File | Current | Central after | Optimistic after | Conservative after |
|---|---|---:|---:|---:|---:|
| 1 | `src/src/Bridge/Operation/Internal.hs` | 459 | 510 | 510 | 510 |
| 5 | `src/workflow/Bridge/Critical.hs` | 1,260 | 1,277 | 1,266 | 1,300 |
| Total | Two files; no new production files | 1,719 | 1,787 | 1,776 | 1,810 |

The four-line customer facade `src/src/Bridge/Operation.hs`, API (25 lines), Signer (93 lines), ATA `Token.Operation`, Cabal manifests and pinned operation-capabilities source stay outside these reduction rows. Their boundaries must be reviewed and their consumers validated, but moving or relabeling their lines is not savings. The consolidated test section owns all test budgets; allowance suggestions below must not be added twice.

## Area 1: reconcile the actual draft deliberately

The working draft changes more than formatting. Its 459 lines are not a smaller compiling replacement established by this design. Relative to HEAD, the preserved diff has 30 added and 81 removed lines. Choosing the committed eleven-workflow contract as the coherent design adds 81 and removes 30, net +51, including all restored helpers; it does not erase the historical draft or pretend its reductions were achieved.

| Draft territory | Concrete inconsistency | Explicit resolution |
|---|---|---|
| Internal 59–75,89–102 | `ResumeSteps` and `NativeSteps` add separate scope/checkpoint/observe/reconcile methods. Critical 541–545 and test/Main 369–373 instead implement shared `CustodySteps`; the respective Resume/Native instances do not implement the new methods. | Use the existing shared internal `CustodySteps` contract. Remove the duplicated four methods from each class, and have resume/native constructors require their own step class plus `CustodySteps`. This is the chosen replacement, not an automatic reset. |
| Internal 77–87,203–240 | `RetrySteps`, `CancellationSteps`, `OwnerFeeSteps`, four evidence families and three workflow constructors are absent. Critical 524–527,578–639,1046–1097 and Main 364–367,412–430,459–473 require them. | Restore all three workflows and their private evidence families. Keep retry, cancellation and owner selection in post-Refl interpretation, with the effect bodies already implemented in Critical. Do not delete consumer methods or coverage to match the incomplete grammar. |
| Internal 248–316 | Only eight interpreter branches remain. The removed retry/cancellation/owner branches carry actual ordering and short-circuit contracts. | Restore eleven explicit branches; preserve all arguments and results. No fallback `RequiredOperation`, arbitrary IO instruction or generic workflow step replaces them. |
| Internal 264–273 and missing combinators | The draft spells cycle traversal locally but CapabilityCompile still references `traverseFlow_`; the committed owner branch also uses `whenFlow`. | Retain the existing two state-preserving combinators, six physical lines including their comment/separator in HEAD. Their type indices must force unchanged state; do not generalize them into retries, compensation or arbitrary actions. |
| Internal 454–459 | `OperatorOperations` dropped `Typeable a` from the quantified `OperatorRepair` constraint, but Critical 574 requires `Typeable result`. | Restore the qualifier at that exact constraint. It supplies type information for full-payload workflow interpretation; relaxing the implementation or inventing an untyped repair path is not the remedy. |

The committed counterpart is exactly 510 lines (`git show HEAD:src/src/Bridge/Operation/Internal.hs`, read only). Using those existing declarations as the target avoids paying to reconstruct removed functionality in different modules. It does not establish a current-tree build. Preserve the snapshot/diff as design evidence, synthesize the chosen changes intentionally in a later implementation phase, and run positive compilation before interpreting any negative compilation failure.

The four local commitments are:

1. Keep `Command caller severity result`, closed `Program` and `Execution` functional dependencies; retain precise Result data families for all four signer routes.
2. Keep `SomeOperationAt Program caller severity result` and nominal caller/severity/result identity from the pinned library. Keep `Plan` nominal. Do not introduce a second wrapper, new interpreter class, arbitrary environment polymorphism or replacement effect framework.
3. Keep both equality checks in Command interpretation: prove the full command payload with `eqT`/`Refl`; after `Restrict` re-hides the carrier, recover that exact carrier inside `withCapabilities` before returning its Flow. Neither proof is runtime financial authority.
4. Keep `Workflow value before after result` interpretation proving all four indices before constructing `F.do`. Each constructor brings precisely its branch's constraints into scope. Flow contains deferred continuations; interpretation does not run effects or acquire an evaluator environment.

`DomainCaps` remains the current five operator and eight worker capability groups. Internal `CustodySteps`, `ResumeSteps`, `NativeSteps`, `SigningSteps`, `BroadcastSteps`, `CycleSteps`, `RetrySteps`, `CancellationSteps` and `OwnerFeeSteps` remain absent from that closed list and from public capability superclasses. A handler must not obtain a granular capability merely because it is allowed to request the corresponding whole workflow. Production MethodStep remains fixed to `Action caller`; a test trace carrier cannot replace that instance.

## Target call and authority map

The following are API contracts, not replacement implementation:

- `checkedOperation :: SomeOperationAt Program caller severity result -> Either Text (Program caller severity result)` remains pure and returns the existing dictionary-mismatch code on failure.
- `evalSafe :: Evaluation 'Safe -> SomeOperationAt Program caller 'Safe result -> IO result` retains SELECT-only resources and public configuration/cache. Safe does not mean pure: DB reads and fixed-label tracing still occur.
- `evalCritical :: MVar () -> Evaluation 'Critical -> Program caller 'Critical result -> IO result` remains private, with exactly one lexical call from `runProcess`'s private dispatch. The gate encloses authorization, the complete chosen effect and its full continuation.
- Private nested worker resolution continues through `checkedOperation` and the worker Execution instance inside the already-held gate. It must not call `runProcess` dispatch or reacquire `evalCritical`'s non-reentrant MVar.
- Private worker-to-signer resolution continues through the closed signer grammar to the bounded pinned-TLS ClientM. Its deliberately internal worker-side evaluation is not public signer authorization. The actual signer request independently enters its own process gate, authenticates and rechecks durable decisions.

There are six explicit Execution instances. Caller/environment rejection stays in them. Local key work stays inside the gated signer branch; the signer environment cannot hold a writer. Worker transport retains no automatic retries, no redirect, fixed CA pin, response-size limit, mode-specific timeout and `signer_outcome_unknown` on ambiguous HTTP failure. `withStableDecision` keeps two fresh reads around the key operation and rejects changed authority before returning a result. No helper caches that first read.

The runtime gate does not cover the separate ATA setup DSL or root lifecycle operations. Keep their existing explicit boundaries; do not claim the one runtime dispatch is the only privileged operation in the product.

## Eleven explicit workflow contracts after Refl

| Workflow | Target sequence and result | Required failure/replay boundary |
|---|---|---|
| Payout | Inspect saved attempts; new work prepares, checkpoints and signs, while saved work selects its exact attempt/family; then queue, checkpoint, broadcast. State goes Text → PreparedPayout → BackupCovered PreparedPayout → SignedPayout → QueuedPayout → BackupCovered QueuedPayout → empty. | Backup markers are sequencing proof, not financial authority. Preserve the new/single-saved/replacement-family paths and every stop prefix. |
| Cycle | Recover first; read permission/paused state; visit candidate payments in order; then try owner selection. | Keep the specific BridgeError catch and custody-deferral rule. Do not convert collected recovery failures into fail-fast traversal. |
| Resume | Paused/boundary check, recover, capture attempts, refresh sources, checkpoint, observe, reconcile, inspect optional unsigned draft, restore if present, final ResumeLedger. | One outer operator scope encloses the full continuation and async cancellation between leaves. |
| Signing | Inspect prepared/saved work; either independently verify saved signature or fresh-authorize/sign/verify/save. | Signing scope pauses with `signing_requires_review`; final authorization/signature validation remains one cohesive primitive. |
| Broadcast | Inspect exact saved intent and current observation; send unseen work or record already observed work. | Broadcast scope pauses with `payment_requires_reconciliation`; refresh/check source and exact bytes after checkpoint and immediately before send. |
| Native rebroadcast | Inspect saved family/review, checkpoint, recheck source/family and authorize exact saved-byte send. | No new principal, inputs or automatic retry. Whole operator scope includes the post-backup checks. |
| Replacement draft | Paused check and saved-result lookup; return saved decision or refresh source, reconcile and issue/validate/save new draft. | Replay order and immutable family/template binding stay explicit. |
| Replacement signing | Paused check and saved-result lookup; return saved txid or refresh source, checkpoint, observe, reconcile, authorize/sign/independently validate/record. | Preserve exact family, draft, prevouts and decoded-byte checks; no broad generic signing helper. |
| Retry approval | Validate input; return matching saved approval before paused check; otherwise require paused state, inspect/validate work, refresh source, prove expiry, reconcile and commit. | Retry replay-before-pause differs from cancellation and must not be normalized away. |
| Preparation cancellation | Validate and require paused state before replay; refresh source, reconcile, reread/validate exact generation, durably BeginCancellation, release saved inputs, FinishCancellation. | Private CancellationCommit binds cleanup to committed work. Never release locks before durable begin; cancellation/error stops subsequent leaves. |
| Owner fees | Obtain saved priority candidates, skip protected/native-input or custody-self cases, try reservations in order, stop after first committed reservation. | Per-candidate freshIntake stays outside the narrow recoverable-error catch. This selects/reserves only; ordinary payout later signs/sends. |

Source checks supporting the nonuniform rules: Critical 585–606 (retry),608–639 (cancellation),648–717 (native replay and fresh issue),962–990 (signing),1004–1030 (broadcast),1050–1097 (owner candidates and catch). Restoring the missing grammar must not shift those concrete leaf checks.

## Area 5: named resources and two bounded replacements

The module is long because it houses concrete effect and recovery policies. The production Flow extraction already happened; moving the signer transport, resource records or effect instances into new files would create navigation changes, not substantial line savings. Do not budget the whole 531–1097 capability region as removable boilerplate.

### Named private resources

Replace the positional seven-field CriticalEnvironment with named fields for RPC
manager, observer settings, Solana policy, customer settings, signing endpoint,
Reader and Writer. Keep constructor/selectors private to Critical.hs and the safe
evaluator's separate narrower environment. Use explicit construction and field
puns at existing use sites; no new class, shared process state or generic effect.

Declaration 2→9 and construction 1→9 plus two explanatory lines cost about 17
lines before wrapping; budget **20/27/40 added lines** for optimistic/central/
conservative layout. The observed 67 constructor-pattern sites can initially be
same-length substitutions, not 67 credited deletions. This improves resource
readability without claiming a source reduction.

### Optional direct dictionary recovery

Critical 75–92 is an 18-line `ExecutionProof` GADT, six-clause proof function, view pattern and COMPLETE pragma. It exists to recover constraints already stored by each Program constructor. The default candidate is explicit constructor cases at the two evaluators: two safe cases and four critical cases. A constrained local critical body contains the unchanged gate/authorize/evaluate code. The known nested worker/signer paths match WorkerDSL and SigningDSL respectively. This retains each stored dictionary and makes the only admitted constructors visible at dispatch.

Do not introduce a new rank-n `withExecution` combinator merely to hide those six cases. Its generic continuation and dictionary plumbing may be harder to audit than the current pattern. If explicit cases need extra type machinery or obscure the gate, retain the existing proof layer. Budget: remove 18 existing lines; add 10–14 lines distributed over evaluator dispatch, centrally 12. Optimistic savings 8, central 6, conservative 0. These replacement lines include the local constrained signature and explanatory comment; unchanged effect bodies are counted unchanged. No build claim is made for the proposed type arrangement.

### Fixed paused-state check

Ten pairs of lines read ReadState then require ledgerPaused with the identical `pause_before_operator_action` code: 549–550,592–593,611–612,673–674,693–694,729–730,742–743,757–758,821–822,836–837. Replace those 20 lines with ten calls to one private `requireOperatorPaused :: Reader -> IO ()` helper, 4–6 lines including its comment/separator. The helper always performs a new closed ReadState operation and uses the fixed code. It accepts neither a query nor an IO callback nor caller-selected error policy.

Keep every call at its original point. In particular, retry checks replay first; cancellation checks pause first; initial operating funding and upgrade checkpoint retain their distinct codes and checks. The helper does not return a reusable authority token or share a snapshot across RPC. Optimistic savings 6, central 4, conservative 0 if a helper is judged less clear than the pairs.

| Nonoverlapping replacement | Old physical lines | Central replacement cost | Optimistic replacement cost | Conservative |
|---|---:|---:|---:|---|
| Proof/view-pattern layer,75–92; same-length known-constructor case substitutions at119,266,409,414 plus allocated new local cases | 18 | 12 | 10 | Keep 18 |
| Ten ReadState/paused pairs above | 20 | 10 calls +6 helper =16 | 10 calls +4 helper =14 | Keep 20 |
| All other Critical lines | 1,222 | 1,222 | 1,222 | 1,222 |
| Named resources, incremental cost within retained bodies | 0 | +27 | +20 | +40 |
| Critical total | 1,260 | 1,277 | 1,266 | 1,300 |

The two cleanup replacements are disjoint; the named-resource layout is an
additional incremental cost within otherwise retained code. Their additions are included. There is no dependency/library reduction, generated-code exclusion, new module, schema change or hidden replacement implementation in this budget.

## Gate, errors and cancellation preservation checklist

- One process-local MVar is acquired by the sole critical evaluator entry. It is released on success, refusal and exception. Worker and signer have separate process gates, not a claimed cross-process mutex.
- Observation-only permission runs before each leaf and before entering operator/signing/broadcast scopes, including result-dependent continuations. A denied scope does not first pause the ledger as an error side effect. Recovery/observation leaves and explicit operator pause retain their current allowed status.
- Operator and broadcast scopes keep `onException` around the entire nested Flow; signing retains its different pause reason. Cancellation between successful leaves remains covered. Flow is not rollback: committed attempts, bytes, postings and cleanup journals persist.
- Cycle catches only BridgeError and retains its exact custody-deferral rule; `tryBridge` still translates IOException but does not swallow AsyncException. The worker loop catches BridgeError, backs off, and allows cancellation/database exceptions to escape.
- `recoverPending` keeps the intentional collected-error order at1137–1147 and the mandatory reconciliation before reporting collected errors. Native source paging keeps complete scan and first-error retention at894–916. Neither is rewritten using ordinary fail-fast Flow traversal.
- Keep state-dependent fresh reads after slow backup/RPC, final exact authorization, and the signer read/sign/re-read. Apparent duplicate checks across those moments or process boundaries are not reduction candidates.
- Keep fixed-label tracing, no credential/request/result logging, and the meaning that `done` denotes return rather than broadcast or settlement.

## Planned evidence, not results

The design has read the full reference/Main.hs, Operation/Internal.hs and Critical.hs, the four-line facade, API, Signer and ATA Operation modules; relevant architecture/current-plan/code-map instructions; CapabilityCompile in full; Main's actual payout/workflow trace compiler and oracles; SigningTransportCheck's worker cancellation case; and StoreCheck's real operator-scope failure/cancellation and HTTPS gate context. The pinned library is `operation-capabilities ==0.1.3.0` at `86c5b86078bc6fe9b9130a28d9de600a339f6221`. Its separate source implementation was not re-audited here; no dependency change is proposed.

Future validation order:

1. First establish positive compilation against the actual merged Internal plus all actual consumers through the Cabal core/customer/workflow/app/test components, one job. No overlay may substitute a different grammar. Until this passes, missing-symbol failures from negative cases prove nothing.
2. Retain all existing CapabilityCompile positive controls and BAD_* cases: caller/severity/result/coercions, selected-capability boundaries, internal-step exclusion, indexed branch composition, and required backup states. Reject missing-name diagnostics as evidence of the intended boundary. Keep the state-preserving traversal rejection if the helper is retained.
3. Retain Main's payout three branches (296–342), full eleven-workflow result/order table (432–474), four-index mismatch checks and every synchronous/ThreadKilled prefix (476–498). These are independent trace expectations, not DB/HTTPS acceptance.
4. Retain the ordinary disposable PostgreSQL contract and separate complete-draft resume contract, then the relevant fresh local worker/signer HTTPS modes. Existing StoreCheck 5233–5276 injects synchronous boundary failure and later async observation failure through real resume; it asserts increased pause count, unchanged attempts/postings/balances and no sends. The HTTP gate/read-again contract around5016 and worker-loop shutdown check in SigningTransportCheck are distinct evidence.
5. Prefer four focused assertions in existing harnesses, only if needed for the changed dispatch/helper: both safe callers still evaluate; caller refusal releases the critical gate; a nested worker request completes without recursive acquisition; a second paused-state call rereads rather than caches state. Suggested separately budgeted allowance is 18–35 test lines, not a new test executable. Existing failure-order/replay tests should carry the pause-helper semantics rather than writing tests mirroring the helper body.
6. Bind the eventual independent review and before/after counts to the exact merged source hash. Historical committed-overlay results and source-presence of tests remain historical evidence, not results for this design.

These validations are future gates only. No new live/funded acceptance, chain truth, deployment approval or compiler success is claimed.

# B. Detailed configuration and lifecycle design

## 2. Configuration: concrete future shape

### Responsibilities and interfaces

`InstallConfig.hs` remains the sole reader of the operator's Haskell-shaped record. Preserve the grammar, declaration-order handling, optional gas defaults, old-record-only `solKeyB58` acceptance, bound checks, secret-free diagnostics and original input bytes. Do not replace it with evaluation of a configuration program or with a second operator example.

Add app-local plain records with no Show instance where secrets are reachable:

- `ValidatedInstall`: original bytes, parsed `InstallConfig`, validated Solana key bytes and `InstallProjection`. Constructor stays private; `readValidatedInstall` performs the existing complete validation once for a particular opened immutable candidate. This is not a cache across replay or mutable-file changes.
- `InstallProjection`: `OperationalSettings`, validated `InterfaceConfig`, `HostingSettings`, and repository bytes. `OperationalSettings` holds the two RPC URLs, typed `PayoutPolicy`, `Maybe GasTopUp`, and `OwnerFeeRecipients`. It contains no custody key. `HostingSettings` holds domain/IP/tunnel-enabled; it never embeds the tunnel token.
- `projectInstall`, `applyOperational`, `installInterface`, `installHosting`, `repositoryBytes`. The first parses exact decimal amounts once; the application functions produce a closed set of typed edits for the authorized JSON fields. Updates apply those edits to the original validated Aeson value, preserving unrelated keys, legacy spellings and absent/null representations; fresh setup may encode a new record. Keep all other Config fields and original sealed bytes unchanged.
- The existing explicit update-field allowlist and key-identity comparison stay in place in this narrower forecast. A future typed classifier must account for every field; it is not a source-saving assumption here. This classifier grants no permission to perform the change: Reconfigure still validates current journals, bindings, target scope and installed state.

`Bridge.Config` remains the owner of runtime decoding/validation, immutable fingerprint, policy adapters and public configuration. Add only a small typed role-path projection/comparison, approximately 18 central lines: `RolePaths`, `applyRolePaths`, and `sameRuntimeSettingsExceptPaths`. The exception list is exactly nativeCookie, nativeUnlockFile, signerAuthFile, fenceDirectory and solanaSdkLibrary. Do not replace full equality with fingerprint equality; the latter deliberately excludes operational settings. Worker projection must always erase nativeUnlockFile. Keep runtime `validateConfig` stricter than `validateSetupConfig` by requiring both real history anchors.

`Configure` continues to own prompts, interactive seed generation and the offline importer; `Bootstrap` continues to own provider/history/ATA effects. Configure uses shared typed policy/interface/hosting projections and role-path comparison; Bootstrap remains unchanged in this budget. The fixed setup/source publication lists remain explicit; no savings are assigned to a new publication-list helper. Different optional fields remain intentional: default interactive setup has no install.conf or hosting.json, and advanced imports retain their different source/reference behavior.

`Reconfigure` keeps all replay, fixed-target, bootstrap seal and installation checks. `configurationFiles` validates each candidate and applies the shared typed field edits to its original JSON value; `verifySetup` uses the same role comparison. `beforeView` and `afterView` remain evidence views over staged immutable snapshots. They must not be replaced with fresh reads after partial publication. `writablePaths`/metadata authorization become closed app-local target constructors only if the helper cost fits; the allowed set itself is not deleted as duplication.

### Before/after paths and effects

Current record path: readInstallConfig -> validateInstallConfig -> Configure validates the same key again -> parse thresholds/top-up again -> hand-build runtime/interface/hosting JSON. Reconfigure repeats the policy, interface, hosting and repository projections. Proposed path: immutable candidate read -> full validation and typed projection -> mode-specific key/source preparation -> same immutable records and bytes -> same setup/runtime validation. Key derivation can be reused within one call; durable replay revalidates original candidate and referenced material.

The secret/private/public split stays explicit:

1. Operator original bytes remain private and are saved verbatim, including comments/order/whitespace.
2. Setup references record source paths; record import preserves supplied keys; only interactive startup may generate keys.
3. Worker and signer Config JSON share operational policy but preserve distinct RPC credentials, unlock access and service paths.
4. Public configuration uses existing `publicConfiguration`; neither original record nor ValidatedInstall is serializable as a public response.
5. Reconfiguration still updates only future policy. Saved quotes, payout round intervals, transaction bytes and identities remain owned by the ledger.

Do not conflate `freshCustodyAttestation`, derived key identity, source-to-installed config equivalence, fingerprint, complete runtime equality or bootstrap-seal bytes. They answer different questions. A regenerated equivalent JSON record must not replace the original private record or a saved seal merely because it decodes to equal fields.

### Per-file estimates and transformations

| File under repository root | Before | Opt / central / conservative target | Central old groups / replacement+new lines | Exact bounded transformation |
|---|---:|---:|---:|---|
| src/app/InstallConfig.hs | 279 | 340 / 359 / 400 | 32 / 112 | Reader region 49–80 (32 lines) ->30 lines of validated-input readers/wrappers. Add 82 lines paid here: types/selectors 24; typed operational parsing/application 22; interface/hosting/repository projection 14; closed authorized field edits 12; imports/comments 10. Preserve the parser, semantic validation and explicit update allowlist. Conservative range pays the optional ~40-line typed-default expansion. |
| src/app/Configure.hs | 745 | 718 / 722 / 735 | 39 / 16 | Precisely: 78–89 (12)->5;120–121 (2)->1;130–139 (10)->5;147 (1)->0;152–153 (2)->1;241–247 (7)->3;687–690 (4)->1;sole parseCoins import 6 (1)->0. Sum39->16. Keep validation at90/95/148, original-byte/key publication, setup/source lists140–146 and248–257, advanced defaults310–323, role records399–407 and template598–601. No other import savings. |
| src/app/Reconfigure.hs | 402 | 305 / 337 / 380 | 117 / 52 | Projection223–251 (29)->10;setup comparison290–322 (33)->27;authorized metadata/read plumbing337–369 (33)->11;local mechanics381–402 (22)->4. Sum117->52; no incidental import savings are budgeted. Fixed target metadata and mechanics are paid once in ReconfigureFiles. All selected-target and replay checks remain. |
| src/workflow/Bridge/Config.hs | 187 | 200 / 205 / 215 | 0 / 18 | Pay for typed role-path comparison/projection; existing strict decoder, validation and fingerprint remain. No deletion claimed. |
| src/app/Bootstrap.hs | 306 | 306 / 306 / 306 | 0 / 0 | Retain unchanged: existing role projections are already two compact updates. No extraction credit. |

These are source-group forecasts, not a patch assertion. All old-group counts are bounded by the cited nonoverlapping physical ranges. Each replacement allowance includes the local calls or retained statements. New shared type/helper costs are listed at their destination rather than treated as free. The central case does not rewrite Configure's template or move startup code; either move alone saves zero.

### Planned checks, not run

Use the existing ConfigureCheck suite rather than inventing a second settings test framework. Preserve the record syntax/reordered/commented/string-gap fixtures; duplicate/unknown/missing fields, legacy candidate refusal, optional gas defaults, no credential-bearing diagnostics; original-byte replay and candidate change refusal. Add a table over every InstallConfig field with expected classification and output projection; independently enumerate expected allowed/frozen fields so a projection helper cannot validate itself. Test equivalent derived keys with different private input syntax, both individual key changes, and strict two-wallet replacement once initialized.

Golden checks must independently compare existing and proposed JSON fields, default semantics, interface shape, role-specific credential/unlock paths, exact fingerprint and public-secret exclusion. Keep Config's legacy minInput/maxInput compatibility and conflicting withdrawal refusal. Exercise setup-only versus runtime history validation, source/installed mismatch, bootstrap seal mismatch, mixed interactive/record mode and interrupted import. Preserve ordinary and gas-top-up quote history tests in the ledger suite; configuration refactoring cannot reinterpret saved customer terms. These are later acceptance requirements, not claims that this audit ran them.

## 3. Installation, updates, recovery and durable files

### Keep procedures distinct; share mechanics only

The current root orchestration is already separate from runtime DSL evaluation. That separation should remain. `Upgrade.continue`, `Reconfigure.updateLocked`/publish, `WalletRotation.rotateWallets`, `RestoreGuide.restoreGuide`/restoreStep and `RestoreActivate.activate` continue to state the ordered procedure in ordinary IO. No new public runtime capability or signer evaluator is needed. Root callers continue to invoke closed CLI operations for ledger/custody work; no SQL or arbitrary Store callback is introduced.

`ReconfigureServices` can become the existing home of a small closed service API, without becoming a workflow interpreter:

- `CustodyService = WorkerService | SignerService | TunnelService`; map internally to fixed systemd names. Keep the optional-tunnel absence rule explicit.
- `ServiceRequirement = Stopped | AbsentOrStopped | AbsentOrStoppedMasked`; `requireServiceState` acquires the needed fixed properties and applies the caller's named requirement. Do not make these three states interchangeable.
- `stopCustodyService`, `publishUpgradeInterlock`, `publishConfigurationInterlocks`, `requireFenceAtReceipt` and `requireFenceAtLeastReceipt` are possible naming improvements only; this narrowed budget retains Upgrade's existing local fence parser/comparison and claims no savings from them.
- `CheckpointKind = ConfigurationCheckpoint | NewBackupCheckpoint` maps to the current immutable filenames. The candidate signer-transition checkpoint in Upgrade remains explicit because it has different binary/config/environment binding and fencing rules.
- Private subprocess plumbing may share bounded error-code handling, but a public `runCommand :: FilePath -> [String] -> IO` is not the new API. Fixed commands keep private constructors. Never introduce automatic retry of checkpoint, signer, restore, retirement or publication because a child exit status was lost.

`ReconfigureFiles` can supply app-only shared mechanics while retaining its existing manifest/old-new publication protocol. It should continue to be separate from financial attempt publication:

- Private existing/new/complete journal records use `savePrivateRecord`: persistent per-record lock, equal-byte replay, one-link publication, file and parent sync.
- Closed service-unit publication shares a fixed-purpose `publishInterlock` implementation between Upgrade and ReconfigureServices. It supports exact existing content and declared mode/owner; destination constructors choose only the existing fixed unit/drop-in paths. Journals bind content before publication; caller still owns service stop/order and daemon reload.
- A closed `SetupTarget`/`UnitTarget` representation selects exact authorized paths and role ownership in the root app. Resolve metadata afresh and enforce the existing caller whitelist on replay. Expose fixed-purpose readers, not a general pathname reader with caller-chosen owner/mode/limit.
- Path/status/ancestor traversal can share mechanics inside this app module only while keeping separate named predicates for root-only ancestors, root-or-current UID ancestors with immediate-parent ownership, and rotation ancestors. Not-found differs from permission error and corrupt entry. Do not silently strengthen/relax accepted policy as a side effect of deduplication.
- Keep NodeSetup's owned-node-config publication as its own narrow primitive with preserved owner/mode and old/new-byte checks. Its two same-file staging/write/fsync/rename sequences can consolidate locally; do not route a node-owned config through a root-private journal policy.

Runtime `Bridge.File` deliberately works on already-open descriptors/handles. Leave that contract and its 33 lines unchanged. Credentials has root/current-UID and shared-token exceptions; Recovery has UID-private archive rules; Fence has persistent flock and a monotonic mutable watermark; AdminKey publishes immutable signed attempts with exclusive hard links. All were read, but none receives a savings allowance here. The existing separation is valuable, not an accidental duplicate to erase. In particular, do not replace AdminKey.savePrivate with ReconfigureFiles.savePrivateRecord: exclusive no-replace attempt publication and equal-byte lifecycle replay are different protocols, and their hard-link/crash behavior differs.

### Ordered effect maps that the design must preserve

| Workflow | Required order and replay behavior |
|---|---|
| Fresh setup | Private original record -> complete key/endpoint/policy validation -> immutable source/setup records -> provider history preflight -> seal -> initialize/verify backup access -> provision guarded node roles -> closed native initialization -> ATA saved-before-submit/bootstrap history -> installer-specific fresh ledger/roles/config/units -> paused service start -> initial accounting -> checked resume -> optional ingress. Record setup cannot generate missing keys. Source installation archives committed HEAD and builds as hws-build. |
| Operational config change, backup unchanged | Validate original/candidate and exact staged file set -> durable manifest/snapshots -> install persistent interlocks/pending -> stop tunnel/worker -> checkpoint with signer available -> receipt durable -> signer blocked and stopped -> exact fence check -> old/new-aware publish -> setup and installed verification -> release interlocks -> caller's ordinary checked startup. |
| Backup credential change | Candidate target access preflight -> pending plus signer blocker -> stop tunnel/worker/signer -> publish candidate credentials everywhere in the fixed set -> verify bytes -> temporarily unblock only signer -> fresh NEW-target checkpoint -> finally block and stop signer even on failure -> exact fence/receipt and published-file recheck -> finish interlocks -> checked startup. On interrupted replay, re-block/stop signer before slow network preflight. The old inaccessible repository must not prevent changing it. |
| Same-schema upgrade | Verify candidate/configuration/identity -> durable pending -> stage authenticated candidate -> worker interlock and stopped check -> if needed, stop signer then publish exact candidate signer override/helper binding -> verify merged command/environment -> signer start -> closed checkpoint/receipt -> signer interlock/stop -> exact fence -> publish reviewed code without replacing ledger/config/keys -> verify/remove only owned transition override -> on replay stop worker again -> nondecreasing fence -> unblocks -> ordinary recovery/reconcile/resume -> completion -> pending unlink and sync. Exact schema hash compatibility remains. |
| Wallet replacement | Validate supplied new identities and dependencies outside retired paths -> complete offline import in staging -> immutable plan plus directory device/inode manifest -> old checkpoint -> closed read-only no-unresolved-work preflight -> retire DB and fence -> durable retirement proof -> stop native-export socket/instances -> inode-bound directory renames and hardening -> completion before source paths may be reused -> preserve node-role bindings -> import supplied new keys -> save replacement binding/config -> finish interlocks. A specifically proven read-only preflight refusal can restore the original services; other errors cannot. Old balances/keys/ledger remain archived and are not swept. |
| Staged restore | Root/stopped/masked/global-interlock validation -> explicit minimum sequence/source-exclusion acknowledgement -> verify exact custody manifest/schema/identity -> role-specific staging under root ancestors -> durable started record before irreversible subprocess -> parsed completed result durable -> keep new ledger paused and native autoload disabled. Started without completed is UNKNOWN, even if the child reported failure; require review rather than automatic retry. |
| Restore activation | Revalidate staged plan/hash/identity/sequence and reviewed bundle -> explicit exclusion acknowledgement -> durable service blocker -> prepare/install recovered material with fresh service credentials -> verify exact restored DB -> persist only verified native wallet autoload -> activation-start marker -> remove blocker -> start and wait -> closed resume/reconcile -> verify unpaused -> completion/enable/retire pending. Any exception re-blocks and stops custody. Copied old-host keys are not revoked by local markers. |

The worker stop and checkpoint are not a database transaction. A checkpoint receipt cannot substitute for signer exit, a unit drop-in cannot substitute for checked merged systemd state, and a completion marker cannot retrospectively justify an unjournaled unknown side effect. Locks solve different problems: lifecycle lock, record-publication fcntl lock, rotation inode binding, runtime gate and worker fence are all retained.

### Per-file estimates and paid shared cost

| File under repository root | Before | Opt / central / conservative target | Central old groups / replacement+new lines | Exact bounded transformation |
|---|---:|---:|---:|---|
| src/app/ReconfigureFiles.hs | 282 | 390 / 412 / 450 | 0 / 130 | Retain all existing282 lines as the budget floor; no unexplained deletion allowance. Pay130 new lines once: closed target/path/metadata mapping63;fixed unit publication35;root reader14;separate ancestor predicates12;exports/error adapters6. Existing private-record, manifest and old/new publication protocols remain. New helpers cannot silently unify caller policies. |
| src/app/RotationFiles.hs | 255 | 221 / 225 / 240 | 42 / 12 | Only214–255 (42 lines): six path/ancestor/journal/status/sync helpers ->12 lines of fixed-purpose aliases/import wiring. Existing ReconfigureFiles import can expand without deleting an import line. Keep211–212 tag validation and all inode/device/overlap/hardening logic. |
| src/app/ReconfigureServices.hs | 259 | 215 / 225 / 250 | 78 / 44 | Unit block166–207 (42)->9;root-reader/ancestor/status/sync225–250 (26)->6;stop209–218 (10)->10. Add19 lines for finite service/requirement types and shared state checks. Total78->44. This pays the distinct stopped/absent/masked policies and retains local command errors, checkpoint and finally behavior. |
| src/app/Upgrade.hs | 366 | 344 / 351 / 366 | 36 / 21 | Only installInterlock247–263 (17)->12;publishUnit311–324 (14)->3;stopped344–348 (5)->2. Add4 lines for imports/closed-target call adapters:36->21. Retain mark111–114,unblock115–117,fence204–213,all signer-transition verification,syncRoot and subprocess error handling. No speculative import deletion. |
| src/app/WalletRotation.hs | 229 | 229 / 229 / 229 | 0 / 0 | Retain unchanged; the helper tail215–229 does not justify a new command adapter. |
| src/app/RestoreGuide.hs | 181 | 178 / 180 / 181 | 7 / 6 | Only stopped154–160 (7)->6 including fixed-purpose call, import and explicit masked-service requirement. Keep restoreStep unknown-outcome protocol. |
| src/app/RestoreActivate.hs | 179 | 178 / 178 / 182 | 3 / 2 | Only service-state loop67–69 (3)->1 fixed call plus1 import. Keep marker169–173 and sync178–179; replacing them did not have demonstrated savings and could change record/error semantics. |
| src/app/RestoreNative.hs | 159 | 154 / 156 / 159 | 6 / 3 | Only root-ancestor function37–42 (6)->2 fixed-policy wrapper plus1 import. Keep stageParent44–54 and sync158–159; the role-owned0711/0700 staging procedure is not shared. |
| src/app/NodeSetup.hs | 213 | 206 / 209 / 216 | 21 / 17 | Only duplicated writer bodies138–147 and202–211 (10 each), plus now-unused local sync154 (1). Replace with2 call lines and15-line local helper including signature/comments. Preserve metadata, different staging prefixes, source comparisons, candidate records and restart. No service-check or import savings. |

Every deletion allowance is now a stated measured source group; no additional unnamed cleanup is counted. Replacement sizes remain uncertain forecasts. The new local NodeSetup helper is paid in NodeSetup; all cross-app file helpers are paid in ReconfigureFiles; finite service/state helpers are paid in ReconfigureServices. Shell scripts and runtime protected-file modules remain unchanged. Splitting procedure bodies or relocating policy would be extraction, not a saving.

### Planned checks, not run

Retain and extend `ConfigureCheck.reconfigureFilesContract`, `privateRecordCrashContract`, `rotationFilesContract`, backup access/timeout/handoff tests, and `RestoreGuideCheck`. A precise implementation acceptance matrix should include:

1. At each journal fsync/publication boundary: kill before write, after write before file fsync, after fsync before rename/link, after rename before parent fsync, after completion before interlock release. Rerun the same candidate; assert original bytes, one-link final records, persistent lock inode, no changed-candidate adoption and no unauthorized mutation. Do not erase uncertain phase markers to make a retry pass.
2. Descriptor policies: symlink/FIFO/nonregular/hardlink substitutions; wrong uid/gid/mode, unsafe immediate parent/ancestor; exact 8-KiB versus 32-KiB bounds; inaccessible/corrupt files not treated as absent. Test service-shared 0640 token and public-certificate exceptions separately from root lifecycle targets.
3. Replacement manifests: duplicate/overlapping paths, mountpoint/different-device refusal, source inode swap, target already present, partial archive hardening, recreation before/after complete, nested credentials' ownership retained, source content and no discarded archive.
4. Lifecycle traces: ordinary update versus backup-target change must have different expected orders; failed new checkpoint always re-blocks/stops signer; workers/tunnel remain blocked on reboot/interruption; no old-repository receipt substitutes for new-target evidence. Retry only TCP readiness probes.
5. Upgrade: changed candidate/config/interface/schema rejection; exact checkpoint fence before code switch; nondecreasing fence only after publication; candidate signer override cannot be changed while signer alive; merged ExecStart/Environment/EnvironmentFiles rejection; remove only journal-owned override; after successful resume interrupted before completion, stop/reconcile again using current ledger.
6. Restore subprocess: success replay uses exact saved result/arguments even with missing child binary; changed args, orphan complete, nonzero exit, invalid output, kill and lost output retain unknown outcome and refuse automatic repeat. No new ledger fallback, no fence adoption or service start during staging. Activation failure re-blocks and stops both services.
7. Fresh disposable Ubuntu acceptance after component checks: real users/systemd/peer PostgreSQL/node backup handoff, interrupted install/reboot, old-wallet preservation, SSH socket activation, unavailable backup, same-schema release transition and a separately fenced restore. Keep unit and fixture evidence distinct from this host-level acceptance. No live/funded action is authorized by this proposal.

No size reduction is accepted until the relevant positive component build, existing negative/contract checks, meaningful failure-prefix checks and independent review are completed on one coherent source baseline. This audit did none of them.

## Coverage and uncertainties

Full source reads for the five area2 files, nine scoped area3 files, and the unchanged boundary/control files in the TSV. `Docs/AGENTS.md`, active beginning of `IMPLEMENTATION-PLAN.md`, `Docs/CODE-MAP.md`, the unmodified 118-line `Docs/reference/Main.hs`, and `Docs/ARCHITECTURE.md` supplied constraints/context. Test sources were searched for existing entrypoints; the consolidated report owns the existing full-source coverage record, targeted deeper test review and test budgets. The selected shell entrypoints/install/node/tunnel files were read in full; other build helpers were not assumed to be duplicates or budgeted for removal.

Main uncertainties are the API shape needed to preserve every source/installed representation, the cost of readable explicit defaults, app-only fixed-purpose file metadata rules, and actual installed-system interruption behavior. Static review cannot establish clean-install behavior, durable storage guarantees under every filesystem/kernel, provider independence, old-host exclusion or recovery success. The target estimates are conditional and may produce net growth while improving auditability. Preexisting untracked architecture-map documents observed in the working tree were not modified.

# C. Detailed Store and conditional SQL design

## Finding and useful target

Store has real organization problems but is not 3,990 lines of removable scaffolding. It already has closed GADTs, private connection ownership, narrow pure Lifecycle decisions, and compact explicit writes. Named records and explicit evidence codecs can improve review while increasing line count. The full proposed Haskell target below is approximately line-neutral to modest growth: central +55 physical lines across the three original files and one new private evidence module; optimistic -49, conservative +186. It does not substantiate a 30% Store reduction. A narrower first change—derive duplicated read projections from their existing table descriptors—has a credible roughly 14-line saving without undertaking all the typed-record work.

Keep the process architecture and public API. Customer/operator/worker requests still pass through the existing caller/severity DSL and the single critical dispatcher. Store.hs remains the owner of opaque Reader/Writer, StoreRead/StoreWrite/setup/backup/restore constructors, transaction lifetime, closed operation interpretation and explicit writes. Organize each financial operation as local typed load → existing pure decision → visible operation-specific mutations. This can first be achieved in the existing module. Do not count splitting the file as a reduction; a later physical split requires a dependency map and its imports/export/type cost. A giant generic Store interpreter, transaction callback in DomainCaps, CRUD service, or universal patch plan is not this design.

Schema owns each physical table/view mapping once. Projection owns pure, closed-purpose Opaleye selections and join predicates. It never executes a query or exports a connection. A new private Store.Evidence module contains selected decoded evidence records and explicit pure readers of existing persisted JSON. It imports neither PG nor Store/chain acquisition. It does not become a generic validation registry. Keep records small: LoadedPayment(view, root, phase) within Store; GenerationAttempt identity; observed event envelope; native settlement/source-loss evidence. A row or decoded record carries data, never reusable permission. Avoid converting every two/three-field tuple into a record; the cost outweighs the benefit.

## Concrete replacements and their safeguards

1. **One descriptor owner.** Schema:137–154,165–168,195–224,287–290 contain duplicated column-name declarations for projections already represented by obligations, attempts, paymentRoots, feeHolds, preparations, preparationCancellations, chainEvents, replacementDecisions, replacementCancellationRows, replacementMemberRows and nativeWinnerChanges. Derive obligationReceipts, intentObligations, attemptIntents, feeReservations, eventHeads, workPreparations, workAttempts, workCancellations, workFees, replacementDrafts, replacementCancellations, winnerHistory and replacementMembers with `fmap`/`selectTable`. `nativeRecovery` may derive from nativeRecoveryDetails only after verifying identical view columns. Retain their current result tuple order, including work-hash preimages. Do not turn read-only projections into exported Table handles. Do not eliminate custodyReport: it is an actual writable column projection and omission of report_json from custody is deliberate. intentIds and legacyHints have provisioning/residual-state consumers, so they are not presumed dead.

2. **Reuse loaded facts only inside one transaction.** Store:1827–1895,1956–2033 repeatedly read/decode the payment root, then preparationState/preparePayment reconstruct it again. Add a small private LoadedPayment result to the root/funding loader. The existing closed ReadPayment still returns PaymentView. Private loaded-preparation code can take this local result, with its exact root ID and generation. It must not escape to handlers, survive RPC/backup, become a cache, or suppress signer read-before/read-after checks. Ready/active/settled/cancelled remain independent of projected review. Preserve exact replay's intentionally weaker freshness requirement: replay grants no new send/sign authority.

3. **Share funding joins, not refund/conversion rules.** Store:1837–1858 and2781–2801 join order, receipt and saved cost limits and decode saved fields. Use one pure relation with two explicit scoped selections—by obligation's bound order/receipt and by the refundable receipt. Keep the operation-specific cardinality/error checks and eligibility/ownership rules visible. A missing join must still fail, not vanish from liability totals. Refund must not start decoding irrelevant quote fields earlier and thereby change its refusal order. Cost/quote/request equality and profile checks remain at their current authorization moments. No saved terms are rebuilt using current configuration.

4. **One exact generation-attempt predicate.** The five-line selections in saveDraft:2101–2105, unsignedPreparation:2136–2140 and cancellationPreparation:2877–2881 are the strongest small Haskell duplicate. A private Projection.attemptsForGeneration takes only payment ID and generation and returns the same IDs with the same LIMIT 1 existence semantics. Each operation retains its different error (`preparation_already_signed` versus `attempt_already_recorded`) and its other guards. Complete drafts remain uncancellable despite a missing attempt. This is 15 measured selection lines → three call lines + nine helper lines, net three fewer.

5. **Name observation evidence joins.** Store:2433–2467, initialization's reviewed outflow query at3248–3256, and classifyTreasurySpend:3288–3300 all relate chain_events to observation_evidence. Share only the hash join and named result shape. Ordinary custody queries require review=0; initial ATA and treasury classification explicitly permit a reviewed outgoing record. Their stream/event consistency predicates are not identical and must stay explicit. Do not add a boolean `allowUnsafe` API or globally relax custodyEvent. Lift repeated structural field decoding to Store.Evidence while retaining fresh fact binding and error names in each closed leaf.

6. **Query families before materializing whole tables.** readSendSubject:2267–2281 currently selects all replacement members/drafts/cancellations, then filters Haskell-side. nativeFamily:3544–3598 selects all winner history/cancellations. Add pure named family projections scoped through attempts.intent_id and their exact decision IDs; retain eight-member validation with a ninth overflow row, generation/template/input/fee checks and cancelled-decision detection. Explicitly retain history for previous verified winners. No LIMIT is allowed to convert an overflow or missing family member into a valid family. Helpers add code; central model charges growth for this change. Preserve current failure order for malformed global rows, or treat any deliberate change as separate behavior work rather than a purportedly identical refactor.

7. **Evidence records are views of bytes, not new encodings.** Focus on Store:2499–2520 (terminal custody proof),3527–3540 (source-loss binding),3876–3910 (native settled costs/proof),3924–3990 (rebroadcast evidence), plus the local field wrappers in2433–2467. Explicit parsers expose typed fields while retaining the original Text/Value for equality, append-only recording and hashes. Preserve nested JSON strings: successful settlement has outer costs/proof with proof itself saved as Text; failed Solana observation has a different shape. Do not switch to generic ToJSON, normalize object keys, re-encode a signedPolicy/draft, or change workHash:1482–1535 tuple/order/null/bool semantics. Historical native receipt lists and compact receiptCommitment variants remain supported at allocateTreasury:3096–3125. The new module is charged 85 lines central, including headers/imports/comments/records/readers; it is not a free relocation.

8. **Bound expensive history only as a separate complete-query experiment.** expireQuotes:1303–1327 can push absence-of-deposit and relevant-phase predicates into Opaleye; custodySnapshot:2469–2544 can page all terminal history and use NOT EXISTS for unreviewed source losses; held/budget sums can aggregate in PostgreSQL. These are performance/readability opportunities, not counted reductions. A no-change quote expiry replay and invalid old rows must retain their observable semantics. Never bound the ledger's total history at 1,000 and silently skip old obligations. Keep Integer/Scientific exactness and overflow refusal rather than switching aggregate results to Int64. Retain publicReport's five-second client/four-second statement bounds and complete original settlement dating. Current customerPayments pagination already keeps only a bounded display summary while checking complete ordered pages; leave it intact initially.

## Locks, sequencing and authority that cannot be shared away

- Store:291–325: Reader has no writer connection/checkpoint; writer lifetime owns advisory worker lock, private connection MVar and optional production filesystem fence composition. Start paused.
- Store:327–468: read-only RepeatableRead transaction and read-role verification for each evalRead. No common reader pool with writable credentials. Signer obtains a fresh durable authorization snapshot separately.
- Store:644–678: under the MVar, ReadCommitted/ReadWrite starts, deployment singleton receives FOR UPDATE before facts, action completes, critical sequence is read and file fence checkpoint fsynced BEFORE PostgreSQL commit. Any uncertain database/checkpoint/commit failure poisons the connection; only a BridgeError with successful rollback permits reuse. Refactoring a decoder must not turn infrastructure failure into BridgeError and inadvertently make the connection reusable.
- No transaction spans chain RPC or remote upload. Restore/fence changes keep their separate admin/advisory/row locks; exported MVCC dump keeps only its required read snapshot and uploads after it closes.
- Keep custody revision, critical sequence, backup sequence, chain checkpoints, operating clock and gate ownership distinct. Sharing functions must preserve number/timing of increments.
- Source/eligibility and backup checks intentionally repeat at preparation, queue, authorization and independent signing boundaries. Pure decisions, projection filters and SQL constraints are separate defenses. Keep all three.
- Keep failed Solana fee booking, source-loss cover/return, original native principal event with later fee-only winner adjustment, immutable payout cohort policy, refund bypass and exact cancellation begin/cleanup/finish ordering. No allowance, reserve or generation disappears to reduce code.

## SQL opportunity and compatibility stop

Measured source contains 20 byte-identical custody trigger bodies: each `UPDATE custody_check SET revision=revision+1; RETURN NEW`. Definition blocks plus their own trailing separators occupy80 lines. Definitions start441,445,449,453,457,461,465,469,473,477,481,526,542,572,600,604,624,628,680,703. They can share one clearly named8-line function; preserve every trigger name, table, INSERT/UPDATE event, timing, row scope and predicate. Do not merge several row triggers into one statement trigger, change revision predicates, or move the bump to Haskell.

A second measured group contains43 unconditional immutable functions occupying169 lines including each block's own separator (some are two/three-line forms). Forty-two start321,325,333,337,341,345,349,353,357,361,365,381,389,393,397,401,409,413,421,433,437,489,514,518,530,534,546,550,584,588,592,596,608,612,616,620,644,648,695,699,707,834; the payout immutable function starts207. Each always raises SQLSTATE23514. Share one fixed trigger function receiving the literal historical message through TG_ARGV[0], with a clearly bounded argument contract and a comment explaining unreachable NEW/OLD returns. Budget12 lines. Preserve all attachment names/timing/order and all43 historical error strings. This is not dynamic SQL or caller-selected policy. Conditional immutability functions, original payment event checks, deferred payment consistency, payout sealing, source approval and replacement lineage predicates remain separate and unchanged.

Keeping the106 existing triggers explicit makes this source transformation approximately249 old function/separator lines →20 new function/comment lines =229 net lines (schema936→707). Optimistic703; conservative716 for clearer comments/argument guards. Do not also count trigger attachments as deleted. Fresh schema would have37 rather than98 functions: 98−20+1−43+1=37, with tables/views/constraints/indexes/106 trigger attachments unchanged. Catalog names of removed functions necessarily change; this is not byte-identical DDL.

**This saving is conditional and excluded from the compatibility-preserving total.** Provision:87–93 hashes the literal schema bytes in ecx_install.receipt and refuses a mismatching retry; archiveTargetGate:241–244 also compares the current schema hash. build/install/install:110 refuses a changed schema.sha256 for upgrades. Merely keeping schema_version23 and table layouts does not preserve installation/update/archive behavior. Formatting-only SQL edits also alter that hash. Old SQL functions in an existing restored dump do not magically change when the source file changes.

Safe current plan: freeze schema.sql exactly and implement only Haskell changes; retain schema23 and all receipts. Do not add a migration, update funded DB function objects, wipe a ledger, relax receipt checks, or silently accept arbitrary same-version DDL. To select the SQL target later, an explicit reviewed release policy must decide compatibility for the exact old/new hash pair and all affected initialization/archive/restore/upgrade paths. A function-only equivalence investigation can compare catalog/trigger signatures and transactional outcomes on two disposable schemas without writing the old ledger. That investigation alone is not authorization to change the receipt or allow two variants. If the one-current-schema/no-migration/exact-hash requirements remain literal, the SQL simplification cannot be shipped to existing installations and its229-line saving must stay outside the committed budget. A fresh-install-only release is not a functionality-preserving update solution.

## Disjoint physical-line budget

Counts include comments/blanks and all new helper code. After values are design estimates, not an implemented patch, proof of deletability, or percentage target. Existing bounded reads and writes are compact; source shrinkage is not the primary payoff. Backup/Provision/Catalog receive zero reduction credit. Lifecycle and all test changes are outside this ownership, so none are double-counted. Two Cabal other-modules additions for Evidence belong to the consolidated build-file budget, not this table.

| File | Before measured | Optimistic after | Central after | Conservative after |
|---|---:|---:|---:|---:|
| src/runtime/Bridge/Store.hs |3990|3850|3920|3980|
| src/runtime/Bridge/Store/Schema.hs |336|320|328|350|
| src/runtime/Bridge/Store/Projection.hs |208|245|256|280|
| src/runtime/Bridge/Store/Evidence.hs (new private) |0|70|85|110|
| src/runtime/Bridge/Store/Backup.hs |422|422|422|422|
| src/runtime/Bridge/Store/Provision.hs |472|472|472|472|
| src/runtime/Bridge/Store/Catalog.hs |70|70|70|70|
| src/schema.sql, compatibility lane |936|936|936|936|
| **Compatibility lane subtotal** |**6434**|**6385**|**6489**|**6620**|
| schema.sql conditional replacement (instead of936 above) |936|703|707|716|
| **Conditional SQL target subtotal** |**6434**|**6152**|**6260**|**6400**|

Thus compatibility lane spans49 fewer to186 more, central55 more. Conditional SQL target spans282 fewer to34 fewer, central174 fewer; it is not currently authorized rollout feasibility. Add retained/new tests and the consolidated build registration cost to any whole-project figure.

Central itemized accounting for Store−70, Schema−8, Projection+48 and Evidence+85:

| Non-overlapping work package | Central Store delta | Schema delta | Projection delta | Evidence delta | Net delta |
|---|---:|---:|---:|---:|---:|
| LoadedPayment root reuse, excluding funding-query hunk; record/wrappers included |−4|0|0|0|−4|
| Bound funding relation/decoder, readPayment/refund query hunks only |−6|0|0|0|−6|
| Three generation-attempt selections→three calls |−12|0|+9|0|−3|
| Event/evidence relation and explicit leaf filtering, SQL-selection hunks only |−16|0|+18|0|+2|
| Scoped native family history, SQL-selection hunks only |−1|0|+21|0|+20|
| Typed evidence extraction, only decoder/field hunks; full new module cost |−31|0|0|+85|+54|
| Descriptor projection deduplication |0|−14|0|0|−14|
| Named row annotations/readable declarations retained in Schema |0|+6|0|0|+6|
| **Total** |**−70**|**−8**|**+48**|**+85**|**+55**|

Detailed after hunk sizes are estimates; the15 existing repeated selection lines and SQL definition counts are mechanically measured. If additional typeclass/product-profunctor machinery, imports, changed error precedence or record conversion grows beyond the conservative row, abandon that slice's size claim and measure it honestly. Do not compensate by deleting explanatory comments or inlining statements.

## Future verification gates, not run here

1. Freeze hashes and reconcile the existing Operation/Internal draft with its consumers before any implementation acceptance. Keep this audit's design verdict separate from a later hash-bound implementation verdict.
2. Actual Cabal components, one job: runtime/test entry for new private modules (not a broad package environment). Preserve public Store export signatures and negative compilation checks forbidding raw connection/query callbacks/internal step authority.
3. Golden saved bytes and work hashes: both sourceWorkHash/paymentWorkHash, absent/null/some optional values, cancelled and replaced generations, successful nested-string proof versus failed Solana proof, native historical receipt-list and commitment variants. Compare exact Text used for equality/hashing; a roundtrip parsed Value alone is insufficient.
4. Existing actual disposable PostgreSQL contracts for preparation reuse/new/refused, replay, concurrent writers and changed facts while waiting on lock; source cover/return, refund/full holds, payout rounds/owner fee admission; zero/one/two-row cardinality failures; generations8/9 and families8/9. Ensure the common query still distinguishes missing from corrupt and does not turn full-history failure into absence.
5. Ordinary cancellation and separate complete-draft resume/refusal contract; uncertain signing response must retain signable draft and refuse cancellation. Exact saved bytes survive cancellation/expiry/retry/restoration.
6. Existing TLS worker/signer re-read/changed-during-signing contracts; backup after queue and freshness recheck before release/send remain separate. Private fact reuse is never accepted across these boundaries.
7. Fencing/rollback/failure-injection at action, checkpoint, COMMIT and rollback; confirm only successful rollback of policy rejection reuses a connection, and ahead-of-ledger file fence remains a refusal. No skipped/doubled custody increments.
8. PostgreSQL query-result comparison on old and scoped family/event queries over mixed old/current/foreign families, previous winners, cancelled drafts, missing evidence and reviewed outgoing ATA; query planning/cost on long history, complete ordered pagination and malformed-history refusal. Benchmark/readability benefits are not presumed from source appearance.
9. Only if the SQL compatibility policy is explicitly selected: compare function/trigger catalog manifests and all106 trigger attachments including alphabetical firing order, return/error contracts, deferred timing, row counts and revisions; exercise all applicable DML rejection cases on disposable DBs; retain six deferred payment and two deferred payout checks; actual pg_dump/restore and installation retry/archive/upgrade under exact manifest rules. Never relabel older tests against different SQL hashes as acceptance.

Planning conclusion: the narrow descriptor/existence sharing is easy and reviewable. Loaded payment reuse and typed evidence are worthwhile design experiments with bounded uncertainty. Full schema consolidation is an unusually concrete source-size opportunity but is blocked from a compatibility-preserving rollout by exact schema hashes. None of these observations is a PASS for implementation, tests, deployment or valuable-fund operation.

# D. Detailed test design

## Target

Keep the existing Cabal components and test entry points. Add at most one
test-only `TestSupport` module, explicitly listed in both applicable components.
It owns labelled QuickCheck invocation, fixture loading, exact BridgeError
assertions, JSON mutation and purpose-labelled private directory lifetimes.
It must not import a production decision to calculate its expected result.
Keep PostgreSQL-specific fixture constructors/interpreter in StoreCheck so there
is no new generic database test API or package. Arrange its contents as explicit
sections: mode selection, resources, fixture interpreter, named scenario groups.
Moving those sections alone saves zero lines.

Replace inline repeated setup within a scenario group with narrow local helpers.
Do not introduce a universal scenario DSL, polymorphic test environment record,
or an automatically ready/backed-up fixture. `ReadyIntake`, `FreshAt`,
`CoverBackup` and `SetPause` remain visible at their existing call sites. Tests
deliberately omit each of those operations to verify refusal.

Within StoreCheck, move reusable read-row conversion, exact SQL error predicates,
closed fixture insertion boilerplate and disposable connection parameters into
local helpers. Keep all application/test fixture row access Opaleye. Retain
infrastructure DDL fault injection, separate reader/writer connections, exact
financial snapshots and real transaction interleavings. Root recovery/live modes
stay separately opt-in; default mode must never start funded/network work.

## Single-command database acceptance, before cuts

Proposed **build/verify-contracts.sh**, 0→100/120/160 lines (optimistic/central/
conservative), wraps existing Cabal-built components; it is not a new test or
application executable. The original 63-line LOCAL-DEVELOPMENT recipe supplies
most of its core. Budget ~25 lines for bounded ownership/cleanup, ~20 for selector
and labelled-result bookkeeping, ~12 for provisioning/source identity and reuse
of built binaries: central 120. No documentation deletion is credited as code
savings. Future implementation must:

- Refuse root, live credentials/config selectors and existing fixture resources;
  acquire a task-owned private cluster, no network listener, no existing ledger.
- Build once with the pinned compiler and one job; resolve exact binary/SDK paths
  and set ecx_bridge_datadir to the package data when invoking binaries directly.
  Clear every mode selector in an isolated child environment before each case.
- Run the eighteen recipe modes, including gas top-up, each against a fresh
  schema-23 database; explicit default/case handling must reject unknown modes.
- Stop that cluster before running ProvisionCheck's separately owned private
  cluster. Count it as a nineteenth logical case with its own result, not a mode
  accidentally skipped by gas/provision environment precedence.
- Retain per-case source hash, selector, exit/result and diagnostic log; missing
  cases or prerequisites fail the batch. Trap cleanup stops only owned processes.
  Retain the eighteen matrix databases/logs for review. ProvisionCheck currently
  removes its own private root even on failure (ProvisionCheck:40); retain its
  stdout/stderr, not a promised surviving database. Changing that cleanup requires
  a separately budgeted change. Avoid concurrent builds or clusters.
- Keep funded recovery, real node/wallet and external RPC modes explicitly opt-in
  and outside this safe local batch. Negative-compile and TLA checks remain
  distinct required evidence; this database command does not claim to run them.

The existing recipe is corrected in documentation now, but the wrapper is **not
implemented or executed**. Add future checks for real sendUnseenPayment through
runProcess/dispatch and the signer transport: exact saved bytes, unknown send
response, restart and duplicate suppression. Pure Flow traces and direct Store
calls do not by themselves cover that composition. Existing tests launch real worker/control and signer processes and cover
scheduling, preparation, transport failure and upgrade checkpoints (StoreCheck:
3899–3915,4855–4914,4925–4939,4951–4983,5192ff). Their presence is not proof
of the full worker broadcast continuation. Inventory them first, add only missing
cases, and budget any new
scenarios separately before calling the entire acceptance plan costed.

## Specific evidence and rough deletion/replacement arithmetic

* StoreCheck: 2441–3239 is the closed fixture grammar/interpreter (~799 lines),
  not expendable mock code. Private row-conversion/error helpers may save
  35–75 net lines here after declarations and explicit failure names.
* StoreCheck: disposable database and reader connection parameters recur in
  liveObserverMain, setupMain, custodyBundleContract, reportCacheMain,
  initialFundingMain, ledgerMain, payoutRoundsMain, gasTopUpMain, fenceMain,
  serverMain, tlsMain, historyProgressMain. Equivalent default-connection
  acquisition can save ~35–60 net lines. Different identity, origin, policy,
  profile, ledger initialization and writer-fence callbacks stay local.
* StoreCheck: repeated scenario-local snapshot comparisons, certificate/HTTP
  fixture parameter construction and homogeneous refusal tables can save
  ~100–180 net lines. Preserve each expected error/status/unchanged-state
  assertion and the operation order. Named subfunctions within tlsMain
  (4672–5309) cost ~20–40 extra lines but remove the long lexical nesting;
  moving its RPC fixture to a file does not count as a reduction.
* StoreCheck central target 5860: roughly 260 lines of net plumbing cleanup
  across those categories, plus ~38 for explicit scenario boundaries and
  ~100 for row-codec/locked-fact equivalence assertions. These are budgets,
  not a claim that 260 exact deletable lines have been proven. The optimistic
  5630 assumes substantially more homogeneous setup is found during patching;
  the conservative 6150 allows for clearer types and missing regression cases.
* ConfigureCheck: private-parent directory helpers at 199–206,261–267,
  1158–1164,1210–1214; importContract's repeated invocation/success/refusal/
  no-secret-output checks (269–605); backupSetupContract's per-cut replay
  (630–693); terminal dialogue (873–1025). Share mechanics, keep all accepted
  and rejected input vectors and actual executable/PTY behavior. Central
  cleanup allowance ~100 lines minus ~46 new projection/policy assertions
  yields 54 saved. Do not copy the production encoder into the expected oracle.
* ChainCheck 746–761,1044–1053; ObservationCheck 233–249;
  SolanaPaymentCheck 320–333,384–392; NativePaymentCheck 598–606,707–711;
  SigningTransportCheck 348–358,446–453,529–532 and RestoreGuideCheck88–102:
  fixture reading, JSON mutation, rejection and temp-lifetime overlap is small,
  and new shared helper cost is charged once (95 central lines).
* Directory helpers have DIFFERENT contracts. Configure file publication must
  use a protected workspace ancestor; many transport fixtures use /tmp; restore
  tests intentionally reject untrusted ancestors and retain privileged outputs.
  Sharing lifetime mechanics must take an explicit purpose/root, not silently
  make all fixtures use the same directory or cleanup behavior.
* `rejects`, `refused`, `failsIO` are not all equivalent. Some demand an exact
  BridgeError, some SQLSTATE + message, and a few intentionally accept another
  exception type. Do not replace them with catch-all success on any exception.
* LifecycleCheck 1156 lines contains the independent arithmetic/history oracle,
  negative controls and shrinkers. Budget zero savings. CapabilityCompile202
  lines and formal131 lines likewise stay. Main498 grows to525 in the central
  plan to check narrowly changed dispatcher and repeated paused reads; source
  tests must first agree with the coherent 11-workflow grammar.

## What becomes clearer

Readers see named arrangements, explicit state-changing fixture operations,
the action under test and independent expected effects. Common plumbing has one
home. A failure names its scenario and expected rejection instead of relying on
a large enclosing function's Boolean. Mode selection and cleanup ownership stay
visible. This is a modest reduction, not justification for discarding tests.

## Safeguards that remain

Integer/overflow/rounding oracles; exact old quote/fee/top-up terms; all payout
round/refund distinctions; failed/ambiguous outcome replay; independent concurrent
connections; transaction rollback, fence-ahead and poisoned writer; retained
signed bytes; authentication and pinned TLS; real child cancellation/SIGKILL;
setup/restore hash and ownership checks; read-only role refusals; explicitly
bounded simulated transport versus live modes; all negative capability cases.
Preserve independent fixture construction where copying production code would
make test and implementation fail together.

## Verification design (NOT RUN)

1. Before changing fixtures, inventory named scenarios, failure reasons, property
   generation/shrink settings, CPP negative cases and environment modes.
2. Run coherent positive component build before each forbidden CPP case; capture
   diagnostics so unrelated missing imports/dictionaries cannot count as proof.
3. Run bridge-test with existing QuickCheck counts, actual configure executable,
   PTY, transport and restore contracts. Run store-check's real disposable PG
   modes separately: ordinary, payout, top-up, TLS canonical/Devnet, complete
   resume, archive/restore/fence, provisioning SIGKILL. A single invocation does
   not cover all modes. Use one job/cluster and clean task-owned processes only.
4. Compare old/new scenario manifests, expected refusal coverage and financial
   records. Add changed-helper tests with independent expected values. Keep
   evidence explicit about which real OS/PG/TLS boundaries ran and which RPC
   replies were fixtures. Do not describe fixtures as funded acceptance.
5. Fresh implementation reviewer compares removed assertions and helper defaults,
   not merely new test pass counts. Production approval remains a separate gate.

Exact per-file target budgets are in [refactor-estimates.tsv](.audit/refactor-estimates.tsv). The source
budget includes new verification assertions but not documentation or future
developer mistakes. There are 14 current test/formal files and 15 proposed with
one helper; no test executable added, no current test file removed.

## Test/formal per-file budgets

These are paid target estimates, not deleted assertions or measured replacement code.

| File | Before | Optimistic | Central | Conservative | Basis |
|---|---:|---:|---:|---:|---|
| `src/test/CapabilityCompile.hs` | 202 | 202 | 202 | 202 | Keep positive control and all forbidden compositions; no savings |
| `src/test/ChainCheck.hs` | 1,195 | 1,140 | 1,170 | 1,205 | Share strict fixture/error/JSON mechanics; preserve independent RPC/effect oracles |
| `src/test/ConfigureCheck.hs` | 1,214 | 1,080 | 1,160 | 1,230 | Consolidate private temporary directories and invocation/secret-leak assertions; budget new projection-policy comparisons |
| `src/test/LifecycleCheck.hs` | 1,156 | 1,156 | 1,156 | 1,156 | Keep independent arithmetic/history models and shrinkers unchanged |
| `src/test/Main.hs` | 498 | 515 | 525 | 545 | Retain 11-workflow traces; budget focused dispatcher/paused-read regression checks |
| `src/test/NativePaymentCheck.hs` | 711 | 690 | 700 | 720 | Share fixture reads and exception mechanics only; keep actual daemon schemas and independent response scripts |
| `src/test/ObservationCheck.hs` | 536 | 505 | 520 | 550 | Share mutation/fixture mechanics; preserve paged-history and chain-specific ownership cases |
| `src/test/ProvisionCheck.hs` | 360 | 360 | 360 | 360 | Keep real disposable PG provisioning/SIGKILL/role/hash contracts unchanged |
| `src/test/RestoreGuideCheck.hs` | 147 | 145 | 155 | 175 | Share fixture mechanics; budget journal/unknown-child-outcome equivalence assertions |
| `src/test/SigningTransportCheck.hs` | 532 | 505 | 525 | 550 | Share temporary-directory mechanism; retain independent trust/hostname/auth/pinning cases |
| `src/test/SolanaPaymentCheck.hs` | 392 | 360 | 375 | 400 | Share fixture mutation/read/error mechanics; retain exact bytes/fees/rent/top-up verification |
| `src/test/StoreCheck.hs` | 5,982 | 5,630 | 5,860 | 6,150 | Factor bounded fixture plumbing/scenario environment; retain explicit readiness/backup steps; budget row-codec/locked-fact comparisons |
| `src/test/formal/SignerPaths.cfg` | 5 | 5 | 5 | 5 | Unchanged model parameters |
| `src/test/formal/SignerPaths.tla` | 126 | 126 | 126 | 126 | Unchanged abstract signer model; no expanded proof claim |
| `src/test/TestSupport.hs` | 0 | 75 | 95 | 130 | New test-only helper: typed error assertions, JSON fixtures/mutations, purpose-labelled private temp lifetime; no financial defaults |
