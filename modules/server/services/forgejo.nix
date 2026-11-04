# Forgejo: the Git forge.
{ config, pkgs, lib, inputs, srv, ... }:
let
  domain = config.fox.server.domain;
  inherit (srv) secHeadersDeferCSP mkLog;
in
{
  # forgejo-noreply: just the domain for commit addresses, e.g. example.net
  # (no "@"). Stays root-only: systemd hands it to Forgejo
  # (services.forgejo.secrets uses LoadCredential), so the forgejo user never
  # reads the file itself.
  fox.server.secretNames = [ "forgejo-noreply" ];
  sops.secrets."forgejo-noreply".restartUnits = [ "forgejo.service" ];

  # Git over SSH goes through the host sshd as the forgejo user. Every key
  # Forgejo writes into /var/lib/forgejo/.ssh/authorized_keys carries a forced
  # command="... forgejo serv key-N" plus no-pty and the three no-*-forwarding
  # restrictions, so a key holder gets git operations and nothing else.
  #
  # Do NOT set services.openssh.authorizedKeysInHomedir = false. It breaks
  # git-over-SSH for forgejo, and the failure is an auth error with no
  # obvious cause. (Mind the near-twins in auth logs: arlo is you, arlofox is
  # the forgejo run user.)
  fox.server.ssh.allowUsers = [ "forgejo" ];

  fox.server.backup = {
    # Repositories, LFS objects, attachments, the authorized_keys file -- and
    # custom/conf/app.ini, which holds SECRET_KEY, INTERNAL_TOKEN and the JWT
    # secrets the module generated on first start. Restore the sqlite dump
    # without app.ini and stored 2FA secrets and tokens are unreadable. The
    # live .db rides along beside its dump.
    #
    # This is also what grows the repository fastest, which scales the monthly
    # --read-data-subset=5% egress with it.
    paths = [ config.services.forgejo.stateDir ];
    # Interpolated from the module's own option, so the backup can't start
    # silently skipping it if a release moves the file.
    sqlite = [ config.services.forgejo.database.path ];
    exclude = [ "/var/lib/forgejo/data/tmp" "/var/lib/forgejo/log" ];
  };

  # The forgejo CLI is how the first admin gets created and how a password
  # would ever be reset.
  environment.systemPackages = [ config.services.forgejo.package ];

  # Native module, not a container. Two consequences:
  #   - It upgrades with the channel via system.autoUpgrade, so it is NOT in
  #     the container-updates loop and must not be added to it.
  #   - services.forgejo.package defaults to forgejo-lts, so this holds an LTS
  #     line rather than chasing every feature release.
  #
  # Repositories live on local disk under stateDir. Do NOT point
  # repositoryRoot at /mnt/music or any other CIFS mount: git's locking and
  # rename semantics do not survive SMB, and the failure mode is corruption,
  # not an error.
  #
  # NixOS-specific trap, already handled by the module: git hooks and
  # authorized_keys entries embed the absolute store path of the running
  # binary, so an upgrade followed by a gc historically broke both. The
  # module's preStart rewrites those paths on every start, which covers both
  # nix.gc above and autoUpgrade below. If it ever drifts anyway:
  #   forgejo doctor check --run authorized-keys --fix
  services.forgejo = {
    enable = true;

    lfs.enable = true;

    # Settings read from files at start-up, so the values stay out of the
    # repo and the Nix store. Just the domain, e.g. example.net (no "@").
    secrets.service.NO_REPLY_ADDRESS = config.sops.secrets."forgejo-noreply".path;

    settings = {
      server = {
        DOMAIN = "git.${domain}";
        ROOT_URL = "https://git.${domain}/";
        HTTP_ADDR = "127.0.0.1";
        # 3001 gatus, 4533 navidrome, 5264/7264/8264/9000 notesnook,
        # 8000 audiomuse, 8080 miniflux, 8090 ntfy. 3000 is the gap.
        HTTP_PORT = 3000;

        # Host sshd, not the built-in server: 22 is already open and already
        # hardened, and this is what makes the remote a plain
        # arlofox@git.arlofox.net:arlo/repo.git that any client handles with
        # no extra configuration.
        DISABLE_SSH = false;
        START_SSH_SERVER = false;
        SSH_PORT = 22;
        SSH_DOMAIN = "git.${domain}";

        # Unauthenticated visitors land on the profile rather than the
        # instance home page, which is Forgejo project marketing ("run the
        # binary", "ship it with Docker") and reads as nonsense on a
        # one-person forge. Signed-in sessions still get the dashboard, and
        # /explore stays reachable -- this changes the front door only.
        LANDING_PAGE = "/arlo";

        # No asset or avatar fetches from third-party CDNs.
        OFFLINE_MODE = true;
      };

      service = {
        DISABLE_REGISTRATION = true;

        # Public. Anonymous browsing and anonymous HTTPS clone both work.
        # Anonymous SSH does not exist -- SSH always authenticates a key --
        # so read-only visitors use the https:// URL.
        REQUIRE_SIGNIN_VIEW = false;

        # Public instance, so without this the account address would sit on
        # the profile page and in the author field of every commit. Commits
        # get <name>@<no-reply domain> instead; the real address stays for
        # login and, if mailer is ever enabled, notifications. The no-reply
        # domain itself (NO_REPLY_ADDRESS) is a secret, set below.
        DEFAULT_KEEP_EMAIL_PRIVATE = true;
      };

      # On for the blog: pushing to it builds and publishes arlofox.net
      # through the runner below. Workflows use plain shell steps only, so no
      # actions are fetched from anywhere.
      actions.ENABLED = true;

      picture = {
        DISABLE_GRAVATAR = true;
        ENABLE_FEDERATED_AVATAR = false;
      };

      session.COOKIE_SECURE = true;

      # No SMTP configured. Until this flips to true the admin address is an
      # identifier and a login handle only -- nothing is sent to it, INCLUDING
      # password resets. With registration disabled, /user/login is the entire
      # auth surface and there is no recovery path but the CLI. Put TOTP on
      # the account and keep the password in Bitwarden.
      mailer.ENABLED = false;
    };
  };

  # secHeadersDeferCSP, not secHeaders: Forgejo sends its own
  # Content-Security-Policy and the plain block would silently replace it
  # with the frame-ancestors-only policy. Confirm after deploy with
  #   curl -sI https://git.arlofox.net/ | grep -i content-security
  #
  # Git over HTTP makes an unauthenticated request
  # first and takes the 401 before retrying with credentials, so every
  # normal clone would feed a 401-counting jail and ban you. Exactly the
  # ntfy and Navidrome problem. Nothing watches this namespace, hence
  # roll_keep 10 -- though a public forge fills it far faster than the
  # rest of these.
  #
  # No basic_auth gate, and there cannot be one: git sends its own
  # Authorization header carrying Forgejo credentials, so a Caddy-level
  # basic_auth would either consume it or reject every push.
  #
  # Caddy has no default request body limit, so there is no nginx
  # client_max_body_size equivalent to set here. Add
  #   request_body { max_size 512MB }
  # inside the handle block if you want a ceiling on pushes.
  services.caddy.virtualHosts."git.${domain}".extraConfig = ''
    ${secHeadersDeferCSP}
    ${mkLog "access" 10 "git.${domain}"}

    # Public forges are a magnet for crawlers walking every commit, blame
    # and archive URL across every ref, which is the usual way a small
    # instance falls over: each of those is a git operation, not a page
    # fetch. Served from Caddy rather than Forgejo's customDir so it does
    # not depend on where a given release puts static overrides. The
    # crawlers that ignore robots.txt are what a Caddy rate limiter would
    # be for later, which needs a plugin build via
    # services.caddy.package = pkgs.caddy.withPlugins { ... }.
    handle /robots.txt {
      root * ${pkgs.writeTextDir "robots.txt" ''
        User-agent: *
        Crawl-delay: 10
        Disallow: /*/*/commits/
        Disallow: /*/*/blame/
        Disallow: /*/*/raw/
        Disallow: /*/*/archive/
        Disallow: /*/*/src/commit/
        Disallow: /explore
        Disallow: /user/
      ''}
      file_server
    }

    handle {
      reverse_proxy 127.0.0.1:3000
    }
  '';
}
