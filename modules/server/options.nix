# The few things that differ between servers, as options. A shared module
# reads them; a host (or a service module) sets them.
#
# Lists here (secretNames, paths, sqlite, ...) merge across modules, so a
# service file can add its own entries without anyone editing a central list.
{ lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  options.fox.server = {
    domain = mkOption {
      type = types.str;
      default = "arlofox.net";
      description = "The domain for the server's public sites (the blog, Git).";
    };

    privateDomain = mkOption {
      type = types.str;
      default = "emberfox.net";
      description = ''
        The domain whose DNS points at the server's NetBird address. Services
        listed in privateSites answer here, only to NetBird peers and the
        server itself, behind one wildcard certificate.
      '';
    };

    secretNames = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "miniflux.env" ];
      description = ''
        Secrets this host uses. Each is the file hosts/<hostName>/secrets/<name>
        (add it with ./secret.sh <host> <name>), decrypted by sops-nix to
        /run/secrets/<name>, root-only unless the service says otherwise.
        Each service module adds its own.
      '';
    };

    privateSites = mkOption {
      type = types.attrsOf (types.submodule {
        options.upstream = mkOption {
          type = types.str;
          example = "127.0.0.1:8080";
          description = "Where Caddy proxies <name>.<privateDomain> to.";
        };
      });
      default = { };
      example = { rss.upstream = "127.0.0.1:8080"; };
      description = ''
        Private sites, by subdomain. Each is reachable only over NetBird (and
        from the server itself). A service adds its own entry. A name may
        have dots: "rss" is rss.<privateDomain>, "auth.notes" is
        auth.notes.<privateDomain>, served from its own *.notes.<privateDomain>
        wildcard certificate.
      '';
    };

    caddy.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether this server runs Caddy (public sites, and the NetBird-only
        sites under privateDomain). A server with no sites turns it off, which
        also closes ports 80 and 443.
      '';
    };

    caddy.public = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether Caddy is reachable from the internet (ports 80 and 443 open
        to everyone). A server whose only sites are NetBird-only turns it
        off: 443 is then open on the NetBird interface alone. Its
        certificate still comes through the DNS challenge, which needs no
        inbound port.
      '';
    };

    ssh.allowUsers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Accounts SSH lets in, besides what the services add (Forgejo adds its git user).";
    };

    monitoring.watchUnits = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Units the health check watches for restart loops, besides every
        Podman container (monitoring.nix adds those). A unit stuck restarting
        never reaches "failed", so nothing else would notice.
      '';
    };

    monitoring.extraChecks = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Extra shell for the 5-minute health check, run as root. Append a line
        to the `problems` array for anything wrong, e.g.
        `problems+=("tunnel down")`; the check alerts and pushes its
        heartbeat as failed. Call tools by full store path: the check's PATH
        is small.
      '';
    };

    backup = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether this server runs the nightly restic backup. Off for a server
          whose state is all in this repo and can be rebuilt from it.
        '';
      };
      repository = mkOption {
        type = types.str;
        description = "restic repository URL for this host, e.g. s3:https://s3.fr-par.scw.cloud/bagger-red.";
      };
      paths = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Paths the nightly backup includes. Each service adds its own state.";
      };
      exclude = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Paths the nightly backup skips.";
      };
      sqlite = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          SQLite files to snapshot with .backup before the backup runs
          (copying a live database can give a torn file). Missing files are
          skipped.
        '';
      };
      prepare = mkOption {
        type = types.lines;
        default = "";
        description = "Extra shell run before the backup, e.g. a pg_dump. Runs before the SQLite snapshots.";
      };
    };
  };
}
