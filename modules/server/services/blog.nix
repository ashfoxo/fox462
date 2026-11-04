# The blog: built on push by a Forgejo runner, served by Caddy.
{ config, pkgs, lib, inputs, srv, ... }:
let
  domain = config.fox.server.domain;
  inherit (srv) notify plainLog secHeaders;
in
{
  # forgejo-runner.env: TOKEN= the runner registration token from Forgejo's
  # Site administration -> Actions -> Runners. Only used to register once; the
  # runner keeps its own credentials.
  fox.server.secretNames = [ "forgejo-runner.env" ];

  # setgid: everything the runner creates stays in the blog group.
  systemd.tmpfiles.rules = [
    "d /var/lib/blog 2775 root blog -"
    "d /var/lib/blog/releases 2775 root blog -"
  ];

  # The blog: plain files from the latest build (see the runner above).
  # current is a symlink each build switches in one step, so a visitor
  # never sees half a site.
  services.caddy.virtualHosts."${domain}".extraConfig = ''
    ${secHeaders}
    ${plainLog domain}

    root * /var/lib/blog/current
    encode zstd gzip

    # Ghost's old addresses, so existing links and feed readers follow.
    # Post and tag addresses are unchanged.
    redir /rss /rss.xml permanent
    redir /rss/ /rss.xml permanent
    @ghostImage path_regexp ghostImage ^/content/images/(?:size/[^/]+/)?(?:format/[^/]+/)?(.+)$
    redir @ghostImage /images/{re.ghostImage.1} permanent

    file_server

    handle_errors 404 {
      root * /var/lib/blog/current
      rewrite * /404.html
      file_server
    }
  '';

  # The blog (an Astro site in its own repo on this Forgejo) is built by this
  # runner on every push to main, and published to /var/lib/blog:
  #   releases/<commit>/   one finished build per commit, newest 5 kept
  #   current -> releases/<commit>/   switched atomically; Caddy serves it
  #
  # "native:host" runs jobs directly on the server, not in a container, as a
  # throwaway systemd user with a read-only view of the system. The only
  # thing it may write is /var/lib/blog, through the blog group.
  users.groups.blog = { };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.blog = {
      enable = true;
      name = config.networking.hostName;
      url = "https://git.${domain}";
      tokenFile = "/run/secrets/forgejo-runner.env";
      labels = [ "native:host" ];
      # What a job can run. Node matches the blog's own dev shell.
      hostPackages = with pkgs; [
        bash coreutils findutils gnugrep gnused gnutar gzip git nodejs_24
      ];
      settings.runner.capacity = 1;
      # Jobs run in /var/lib/blog/work. The runner's own state directory is
      # mounted noexec by systemd (DynamicUser), so npm's build tools
      # (esbuild) cannot run there.
      settings.host.workdir_parent = "/var/lib/blog/work";
    };
  };

  systemd.services.gitea-runner-blog.serviceConfig = {
    SupplementaryGroups = [ "blog" ];
    ReadWritePaths = [ "/var/lib/blog" ];
    UMask = "0002";
  };

  # A failed build writes /var/lib/blog/build-failed (commit and log link).
  # The runner cannot read the ntfy token, so root sends the alert instead.
  systemd.paths.blog-build-failed = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathModified = "/var/lib/blog/build-failed";
  };
  systemd.services.blog-build-failed = {
    description = "Push an ntfy alert when a blog build fails";
    serviceConfig.Type = "oneshot";
    script = ''
      [ -s /var/lib/blog/build-failed ] || exit 0
      ${notify} "${config.networking.hostName}: blog build FAILED" \
        "The live site is unchanged. $(cat /var/lib/blog/build-failed)" \
        high
    '';
  };
}
