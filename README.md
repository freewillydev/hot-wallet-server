# Hot Wallet Server

Wrap/unwrap ECX betanet and wrapped ECX on Solana Mainnet, with a 1% fee each way.
Requires Ubuntu 24.04 x86_64, 8 GB RAM and a 256 GB SSD.

1. **Run the installer** from this repository:

   ```sh
   sudo ./build/install.sh
   ```

   It creates a private configuration file with root-only permissions.

2. **Edit the configuration**, replacing the placeholders in [example.conf](example.conf)
   while keeping its Haskell record syntax (`InstallConfig { field = value, ... }`):

   ```sh
   sudo nano /root/hot-wallet/server.conf
   sudo ./build/install.sh
   ```

   Supply unused wallet seeds, two independent Solana RPC URLs and backup settings.
   `solSeedBip39` takes 12 lowercase English BIP39 words separated by single spaces.
   It uses Solana account `m/44'/501'/0'/0'`, with no additional passphrase.
   For `ownerEcxXpub`, paste your ECX wallet's **Receive address** in
   quotes (e.g. from the eCash mobile wallet). The field also accepts existing
   xpubs. `ownerSolPubkey` is your Solana wallet's Receive address. These can match
   the bridge wallets; matching destinations keep earned fees in the bridge.

3. **Fund the SOL address** printed as `Fund SOL fees at:` with **0.01 SOL on
   Solana Mainnet**, in one operator-owned transfer. Wait for confirmation, then
   rerun `sudo ./build/install.sh` with the same configuration. Do not send again
   merely because the installer needs another retry.

4. **Deposit ECX and wrapped ECX** after startup reports `Bridge ready`.
   Send ECX betanet coins to the printed ECX funding address, and the configured
   canonical wrapped ECX token on Solana Mainnet to the printed inventory owner.

To update the config, edit `/root/hot-wallet/server.conf`
with `sudo nano`, then run:

```sh
sudo ./build/update-config.sh
```

This saves the old settings privately, applies supported changes and restarts
through the normal checks. To replace initialized wallets, supply **two new unused
seeds**; old keys and the ledger are retained with root-only access. Pending payments
must finish first. Old balances stay in the old wallets. See [update details](Docs/INSTALL.md#changing-the-configuration).

[Verification records](Docs/DONE.md) ·
[Updates and installation details](Docs/INSTALL.md) · [Operations](Docs/OPERATIONS.md)
