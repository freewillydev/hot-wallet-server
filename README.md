# Hot Wallet Server

Exchange ECX betanet and wrapped ECX on Solana Mainnet, **1:1 before a 1% fee
in each direction**. Customers follow payment instructions; no wallet connection.

**Ubuntu 24.04 x86_64 · i3 or better · 8 GB RAM · 256 GB SSD · sudo · internet**

**Not production approved:** implementation and local tests are available, but
deployment, real-wallet and security acceptance remain open. Keep public access
off; see [remaining work](Docs/DONE.md).

## Configure

Run the installer once. It creates `/root/hot-wallet/server.conf` from
[example.conf](example.conf) with root-only permissions, then stops for editing:

```sh
sudo nano /root/hot-wallet/server.conf
```

No manual `chmod` is needed. Replace the placeholders, keeping **every field**.
The file contains one Haskell record:
`InstallConfig { field = value, ... }`.

- Text uses double quotes: `domain = "swap.example.com"`.
- Whole numbers are unquoted: `minimumPayoutIntervalHours = 48`.
- Exact coin amounts are quoted: `payoutThresholdEcx = "0.001"`.
- Optional values use `Nothing` or `Just "value"`, as with `cloudflareTunnelToken`.

Separate fields with commas inside the braces. This is data read by Haskell's
`Read`, not a program: do not add `module`, `import` or a `config =` prefix.

Supply the ECX recovery phrase, Solana base58 private key, two independent RPC
URLs and backup settings. Keys are imported; missing or invalid keys stop setup.
Keep the default `resticExecutable`; the installer provisions that reviewed backup tool.
New wallets are generated only through interactive startup. Fresh installation
requires unused custody; existing custody needs ledger restoration.

For Cloudflare, create a remotely managed tunnel with `domain` routed to
`http://127.0.0.1:8080`, then put its token in `cloudflareTunnelToken = Just "..."`.
The installer supplies the pinned connector and checks the public deployment identity.
`Nothing` keeps access local. `serverIp` is saved inventory information, not a bind
address or a DNS change. Cloudflare account setup and policies remain external.
Do not enable public ingress before the release/security checks pass.

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
sudo ./build/install.sh
```

Alternatively, run the reviewed `.run` installer with `sudo sh ./ecx-bridge-ubuntu-24.04-x86_64.run`;
it creates the same private configuration file. Edit it, then rerun to install.
Existing configuration is never overwritten. Once setup has bound the record,
changing it requires a reviewed reconfiguration; the updater changes code only.
Rerun the source command with unchanged configuration to resume. Keep independent
ledger backups: wallet keys alone do not recover pending transfers.

## Update

Rerunning `install.sh` resumes setup; use the separate updater for a new version.
In `/root/hot-wallet/server.conf`, set `updatePublicKey` to the independently
trusted release public key, `updateReleaseDirectory` to the downloaded signed
release directory (`.run`, `release-index.json`, `release-index.sig`), and
`updateSetupDirectory` to your original setup directory. Then run:

```sh
sudo ./build/update.sh
```

This requires an installed version supporting configuration-based updates. Older
versions need the [one-time upgrade](Docs/INSTALL.md#older-installed-versions)
first; add the three fields above to their configuration file.

Interactive installs normally use `/var/lib/ecx-bridge-setup/.ecx-bridge` for the
setup directory. The updater verifies the signature,
checkpoints custody to backup, updates code and checks readiness before resuming.
Keys, ledger and settings are retained. A changed schema is refused. After an
interruption, rerun the same command; never delete the upgrade journal. This flow
still requires clean-host and interrupted-upgrade acceptance before production use.

[Operations and recovery](Docs/OPERATIONS.md) · [Architecture](Docs/ARCHITECTURE.md) ·
[Source builds](Docs/LOCAL-DEVELOPMENT.md) · [License](LICENSE)

[Agent instructions](Docs/AGENTS.md) · [Development status](Docs/DONE.md) · [Resume](Docs/RESUME.md)

Only the current database schema is supported. Upgrades with a different schema
are refused; keep the existing ledger and backups.
