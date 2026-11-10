# ferret-amber

The phone: a Pixel 10 running [GrapheneOS](https://grapheneos.org). It isn't
built by this flake (there's no NixOS on it, so this folder holds only this
README), but it's part of the same setup. It reaches the servers over
NetBird, sends all its traffic out through fox-green, and shares `~/sync`
with the laptop and fox-red.

Everything here is set by hand on the phone. This page is the record of
what's set and why. Like the rest of the repo, these are one person's
choices for their own threat model, not a recipe (see the
[root README](../../README.md)).

## Network

**Always-on NetBird, with lockdown.** NetBird is the phone's always-on VPN
with "block connections without VPN" turned on, so nothing leaves the phone
outside the tunnel. Its exit node is `fox-green-mullvad`: traffic goes
through fox-green and out through Mullvad, with fox-green's kill switch
behind it ([fox-green § The exit nodes](../fox-green/README.md#the-exit-nodes)).
For sites that block Mullvad, switch the exit node to `fox-green-direct`.

The same tunnel reaches the private services on fox-red (music, RSS, notes,
podcasts, video), so none of them need to be public for the phone.

**Private DNS** is [Quad9](https://quad9.net) (`dns.quad9.net`), set in
Android's Private DNS setting. It's encrypted, blocks known-malicious
domains, and works through either exit.

**Carrier: [Cape](https://cape.co).** Chosen because it markets itself
around privacy: by its own account it keeps little about its subscribers,
and porting the number out needs a recovery passphrase, which should make a
SIM-swap takeover harder. Its app asks for background location, for its Network Lock feature. Cape has not received **any third-party audits**.

As best I can tell from latency and traceroutes, Cape's core network runs
in AWS and reaches the internet around Ashburn, Virginia. That guess is why
fox-green is in New York ([fox-green](../fox-green/README.md)). If it's
wrong, the exit nodes still work, just with a little more latency.

## Hardening

- **GrapheneOS** on a **Pixel 10**, with its defaults kept: verified boot
  with the hardware security chip, and the phone's storage encrypted until
  first unlock.
- **USB-C set to charging only**, so a cable can't carry data while the phone
  is locked or unlocked.
- **No terminal or shell apps.** Nothing on the phone holds an SSH key into
  the servers.
- **Network access is removed** from apps that don't need it, such as the
  photo viewer that pairs with the camera.
- **App locks** on the sensitive apps use the device lock rather than
  separate PINs: one strong unlock instead of several weak ones.

## Two-factor codes

Most accounts have two second factors: a hardware key and an authenticator
app on the phone. The key is the everyday way in, and it can't be phished.
The app is there so that no single lost or seized device locks you out. If
the key is gone, the phone still gets you in, and the app's codes can be
restored onto a replacement phone if the phone goes.

## Apps that talk to the servers

| App | Talks to | Notes |
| --- | --- | --- |
| NetBird | the NetBird network | always-on VPN, exit node `fox-green-mullvad` |
| Syncthing-Fork | fox-red, and the laptop when it's on | the `sync` folder in internal storage; fox-red only ever gets it encrypted |
| Molly (Signal) | Signal, with push through MollySocket and ntfy on fox-red | no Google push |
| ntfy | `ntfy.emberfox.net` | server alerts and Molly's push |
| Notesnook | `notes.` | self-hosted sync (server addresses in [fox-red § Lessons](../fox-red/README.md#lessons-worth-keeping)) |
| Music, podcasts and video players | `music.`, `spoken.`, `jellyfin.` | NetBird only |
| Gadgetbridge | nothing online | exports to `sync`, charted on the laptop by `health` |

## Backups

The phone has no backup service of its own. Apps whose data matters (Molly,
Gadgetbridge) export into `sync/PhoneBackup` on a schedule. Syncthing carries
that to the laptop, whose nightly restic backup and Filen pick it up. Nothing
has to be done by hand.
