# fox-grey

My own user account on a family Windows PC, used only for Minecraft. It
isn't built by this flake (there's no NixOS on it, so this folder holds only
this README).

It plays the same Prism Launcher instances as the laptop: worlds, mods,
configs and resource packs, synced both ways with Syncthing.

## How it syncs

```
fox-grey ──internet──► fox-green relay ◄──── fox-red ◄──NetBird──► laptop
          (registers, waits)              (dials fox-grey)
```

- **Not on NetBird**, because the PC isn't mine to put on the private
  network. It reaches the others through a private Syncthing relay on
  fox-green ([`syncthing-relay.nix`](../../modules/server/services/syncthing-relay.nix)),
  which only devices holding its token can register with.
- **It pairs with fox-red only.** fox-red is always on, so fox-grey gets
  the laptop's latest instances, and the laptop gets fox-grey's, without
  both being on at once.
- **fox-red holds the instances encrypted**, as it does for the laptop.
  fox-grey encrypts toward it with the `minecraft-instances` folder password.
- **Only Minecraft.** `~/sync` and everything else stay off this PC.

## Setup script

With Syncthing installed and running, paste into PowerShell (no admin):

```powershell
cd $env:TEMP; Invoke-WebRequest https://git.arlofox.net/arlo/fox-den/raw/branch/main/hosts/fox-grey/setup.ps1 -UseBasicParsing -OutFile setup.ps1; powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

It does the rest ([`setup.ps1`](setup.ps1)), asking for the relay token
and the `minecraft-instances` folder password.

## Why only Minecraft

Others have admin rights on this PC and its disk isn't encrypted, so anyone
with either can read what's on it. That's fine for Minecraft worlds and
nothing else.

The most a compromise here can reach is the Minecraft instances and the
relay's bandwidth. To cut it off, take fox-grey out of
[`lib/syncthing.nix`](../../lib/syncthing.nix) and redeploy fox-red, and
change the relay token on fox-green.
