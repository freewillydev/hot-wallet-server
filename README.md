# Hot Wallet Server

A connection-free ECX ↔ wrapped ECX bridge: Haskell/Servant server, separate
signer, PostgreSQL ledger accessed through closed Opaleye operations, and a
browser interface compiled from Haskell. Swaps use existing inventory and charge
1% each way. Mint authority and liquidity-pool administration are not included.

This standalone extraction is under development. The unattended installer,
configurable customer payout rounds, and final deployment acceptance are not yet
complete. Keep public access disabled; see [DONE.md](DONE.md) for the gates.

## Install and configure

Target: Ubuntu 24.04 / Ubuntu Server, i3-class CPU or better, at least 8 GB RAM
and a 256 GB SSD. The managed native-node installer currently targets x86_64.

The sole unattended entry point is:

```sh
sudo ./install.sh /absolute/private/server.conf
```

Supply a private configuration file using the Haskell record in
[example.conf](example.conf). It is parsed as data with `Read`, never executed or
sourced as a script. Replace placeholders before installation. Keep the real
file outside Git; it contains custody keys and provider credentials. The installer
retains an immutable root-private copy and refuses changed inputs on retry.

External prerequisites are independent inputs: two independent Solana Mainnet
RPC URLs, an HTTPS restic repository and its encryption password, the reviewed
restic executable path, and the requested wallet/owner/public-link values. The
current draft validates but does not yet apply all scheduling, ownership and
Cloudflare settings. Those must be wired and verified before this installer is
ready for use. The included 48-hour payout interval is intended to be configurable,
with all eligible orders admitted together; it is not implemented yet.

### Wallet identity

- With a configuration file, **both supplied hot-wallet keys are required**.
  `ecxSeedBip39` imports a valid 12-word English BIP-39 ECX phrase;
  `solKeyB58` imports a base58-encoded 64-byte Solana keypair and verifies its
  public half. Empty, missing or invalid input fails; there is no wallet-generation
  fallback. Repeated installation retains exactly the same imported identity.
- For the optional interactive flow, `configure` saves settings without creating
  wallets. `start` creates them with a terminal and recovery acknowledgement.
  `configure --advanced` supports imports/restoration; `start --advanced` also
  permits new-wallet generation.
- Internal RPC passwords, signer authentication and wallet-unlock credentials are
  separate from custody keys and may be generated automatically.

Fresh setup requires **unused custody with no existing bridge ledger**. Importing
keys does not reconstruct outstanding customer obligations. Used wallets require
reviewed ledger/custody restoration; never initialize a fresh ledger over them.
Keep the ledger, key material and backup password in independent backups.

## Source and verification

Production sources, Cabal components, schema and focused tests are under `src/`.
Build from this repository root with the pinned toolchain:

```sh
cabal build exe:ecx-bridge -w ghc-9.14.1 -j1
cabal test bridge-test -w ghc-9.14.1 -j1
```

Cabal also builds the GHC JavaScript interface and bounded Solana SDK FFI; their
native toolchain prerequisites are in [source development](docs/LOCAL-DEVELOPMENT.md).
Use [AGENTS.md](AGENTS.md) for the verification map and [RESUME.md](RESUME.md) for
current work. No Linux installation or production readiness is implied by a
successful local build.

Extracted from the server subtree of
[ecx-solana-bridge at 6af7e738](https://github.com/freewillydev/ecx-solana-bridge/tree/6af7e73818c041669c5a5c1819f4c5c0be405d37/2-Wrap-Unwrap-Server).
Inherited architecture and release documents describe that source history;
new-repository acceptance is recorded separately in DONE.md.

[Architecture](docs/ARCHITECTURE.md) · [Operations and recovery](docs/OPERATIONS.md)
