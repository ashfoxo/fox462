{ pkgs, ... }: {
  # C toolchain and friends.
  #
  # Imported from home/desktop/default.nix. Everything here is user-scoped on purpose -- none of
  # it needs to exist before login, and keeping it out of
  # environment.systemPackages means a broken experiment can't wedge a rebuild
  # of the system closure.

  home.packages = with pkgs; [
    # --- Compilers ---
    gcc                 # provides cc, gcc, g++, cpp, gcov

    # DO NOT also add `clang` here. Both gcc and clang install bin/cc and
    # bin/c++, and two derivations claiming the same path in one profile is a
    # buildEnv collision -- home-manager will fail the activation with
    # "collision between ... /bin/cc". If you want to cross-check a warning
    # against clang, get it per-project:
    #
    #   nix shell nixpkgs#clang -c clang -Wall -Wextra -fsyntax-only src/main.c
    #
    # or add clang to a project devShell, where it's the only compiler present.

    clang-tools         # clangd, clang-format, clang-tidy, WITHOUT bin/cc.
                        # This is the whole reason this attribute exists
                        # separately from `clang`. It is the language server,
                        # not a second compiler.

    # --- Build / introspection ---
    gnumake
    bear                # wraps a build to emit compile_commands.json:
                        #   bear -- make -B
                        # clangd reads that file to learn your real flags.
    pkg-config          # inert without a devShell; libraries aren't on any
                        # global search path under nix. Included so that when
                        # you do open a devShell with a library in buildInputs,
                        # `pkg-config --cflags libfoo` works from the same
                        # terminal you were already in.

    # --- Debug / correctness ---
    gdb
    cppcheck            # static analysis, runs standalone, no build needed
    # valgrind          # intentionally commented. The sanitizers baked into
                        # the template Makefile (ASan/UBSan) catch a superset of
                        # what you'll hit while learning, run ~50x faster, and
                        # don't have valgrind's periodic "unhandled instruction"
                        # breakage against a new glibc. Uncomment if you
                        # specifically want callgrind or massif.

    # --- Documentation ---
    man-pages           # section 2 and 3: `man 3 printf`, `man 2 open`
    man-pages-posix     # section 3p: the standard's wording, not Linux's
                        # NOTE: `man 3 printf` will be missing until these are
                        # installed AND you open a new shell. If section 3 still
                        # 404s, see documentation.dev.enable in the notes.
  ];

  # direnv: the piece that makes per-project toolchains bearable.
  #
  # Without it you type `nix develop` every time you cd into a project, and the
  # resulting shell is a subshell your editor didn't inherit. With it, cd'ing
  # into a directory containing .envrc puts the project's compiler and libraries
  # on PATH automatically, and cd'ing out removes them.
  #
  # The nix-direnv half matters for a second reason specific to this config:
  # nix.gc runs weekly with --delete-older-than 30d. A plain `nix develop`
  # shell has no GC root, so a month later the store paths are collected and
  # your next build silently re-downloads a compiler. nix-direnv writes GC roots
  # into the project's .direnv/ directory, which lives under /home -- a separate
  # btrfs subvolume the impermanence wipe never touches. So project toolchains
  # survive both the weekly GC and every reboot.
  #
  # This hooks itself into bash automatically because programs.bash.enable is
  # already true in home/default.nix. It would have been silently inert otherwise --
  # same failure mode as the sessionVariables comment in that file.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
