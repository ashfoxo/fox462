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
        from the server itself). A service adds its own entry.
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

    backup = {
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
