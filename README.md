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

   Supply unused wallet keys, two independent Solana RPC URLs and backup settings.
   Keep public access disabled until [release checks](Docs/DONE.md) pass.

3. **Fund the SOL address** printed as `Fund SOL fees at:` with **0.01 SOL on
   Solana Mainnet**, in one operator-owned transfer. Wait for confirmation, then
   rerun `sudo ./build/install.sh` with the same configuration. Do not send again
   merely because the installer needs another retry.

4. **Deposit ECX and wrapped ECX** after startup reports `Bridge ready`.
   Send ECX betanet coins to the printed ECX funding address, and the configured
   canonical wrapped ECX token on Solana Mainnet to the printed inventory owner.

**Not production approved yet.** [Release status](Docs/DONE.md) ·
[Updates and installation details](Docs/INSTALL.md) · [Operations](Docs/OPERATIONS.md)
