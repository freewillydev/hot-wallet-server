# Hot Wallet Server

Exchange ECX betanet and wrapped ECX on Solana Mainnet, **1:1 before a 1% fee
in each direction**. Customers follow payment instructions; no wallet connection.

**Ubuntu 24.04 x86_64 · i3 or better · 8 GB RAM · 256 GB SSD · sudo · internet**

**Under development:** unattended installation, payout scheduling and some config
settings are unfinished. Keep public access off; see [remaining work](DONE.md).

## Configure

Save a copy of [example.conf](example.conf) as a private `server.conf` outside
Git, then replace the placeholders. It contains one Haskell record:
`InstallConfig { field = value, ... }`. Keep **every field** from the template.

- Text uses double quotes: `domain = "swap.example.com"`.
- Whole numbers are unquoted: `minimumPayoutIntervalHours = 48`.
- Exact coin amounts are quoted: `payoutThresholdEcx = "0.001"`.
- Optional values use `Nothing` or `Just "value"`, as with `cloudflareTunnelToken`.

Separate fields with commas inside the braces. This is data read by Haskell's
`Read`, not a program: do not add `module`, `import` or a `config =` prefix.

Supply the ECX recovery phrase, Solana base58 private key, two independent RPC
URLs and backup settings. Keys are imported; missing or invalid keys stop setup.
New wallets are generated only through interactive startup. Fresh installation
requires unused custody; existing custody needs ledger restoration.

## Install

From the repository directory:

```sh
sudo ./install.sh /absolute/private/server.conf
```

Rerun the same command with unchanged configuration to resume. Keep independent
ledger backups: wallet keys alone do not recover pending transfers.

[Operations and recovery](docs/OPERATIONS.md) · [Architecture](docs/ARCHITECTURE.md) ·
[Source builds](docs/LOCAL-DEVELOPMENT.md) · [License](LICENSE)
