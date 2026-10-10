# Hot Wallet Server

Exchange ECX betanet and wrapped ECX on Solana Mainnet, **1:1 before a 1% fee
in each direction**. Customers follow payment instructions; no wallet connection.

**Ubuntu 24.04 x86_64 · i3 or better · 8 GB RAM · 256 GB SSD · sudo · internet**

**Under development:** unattended installation, payout scheduling and some config
settings are unfinished. Keep public access off; see [remaining work](Docs/DONE.md).

## Configure

On the Ubuntu server, create a root-only copy of [example.conf](example.conf)
outside Git. Run the copy commands only for first setup; afterward edit the
existing file to preserve your keys/settings:

```sh
sudo install -d -o root -g root -m 700 /root/hot-wallet
sudo install -o root -g root -m 600 example.conf /root/hot-wallet/server.conf
sudo nano /root/hot-wallet/server.conf
```

Directory mode `700` and file mode `600` restrict access to root. Replace the
placeholders, keeping **every field**. The file contains one Haskell record:
`InstallConfig { field = value, ... }`.

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

## Custom website

Set this field in `server.conf`:

```haskell
websiteDirectory = Just "/opt/my-website"
```

Supply `index.html`, `style.css` and `dist/wallet.js` in that directory. HTML loads
`/style.css` and `/wallet.js`. Use root-owned files (`644`) and directories (`755`),
with local scripts/styles rather than inline code or CDN dependencies.

`Nothing` keeps the default interface. Custom files survive code upgrades;
the customer API is unchanged. See [website details](Docs/OPERATIONS.md#custom-website).

## Install

From the repository directory:

```sh
sudo ./build/install.sh /root/hot-wallet/server.conf
```

Rerun the same command with unchanged configuration to resume. Keep independent
ledger backups: wallet keys alone do not recover pending transfers.

[Operations and recovery](Docs/OPERATIONS.md) · [Architecture](Docs/ARCHITECTURE.md) ·
[Source builds](Docs/LOCAL-DEVELOPMENT.md) · [License](LICENSE)

[Agent instructions](Docs/AGENTS.md) · [Development status](Docs/DONE.md) · [Resume](Docs/RESUME.md)
