{
  description = "carpenter dotfiles — nix-darwin + home-manager, thin out-of-store wrapper";

  inputs = {
    # Pinned to the 26.05 stable line to mirror the reference repo. Bump to the
    # current stable darwin channel (and the matching nix-darwin/home-manager
    # release below) when rolling forward.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Escape hatch for tools whose upstream release cadence outruns the stable
    # channel's backport window — the allowlist lives in
    # modules/home/packages.nix. This input IS nixpkgs (no separate input), so
    # no `follows` is set.
    #
    # Pinned to a REV, not the branch, for two load-bearing reasons: (1) the
    # updater soak-window in scripts/update-unstable.sh needs a fixed rev to
    # record first-seen time before promoting ~7 days later — commit timestamps
    # are not trusted as channel tips; and (2) a rev cannot be moved by a bare
    # `nix flake update`, so bumping is always deliberate + reviewable. Reverting
    # to a branch name silently disables both and fails the assertion in
    # scripts/test-nix-review-regressions.sh.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/70ce234312134a463ba7728e94da2486a1d237ac"; # nixpkgs-unstable @ 2026-08-06
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      nixpkgs-unstable,
    }:
    let
      machines = import ./lib/machines.nix;
      systems = nixpkgs.lib.unique (map (host: host.system) (builtins.attrValues machines));

      # Canonical capability keys, defined by this repo's own rows. External
      # host rows (wrapper flakes calling lib.mkHost) must carry AT LEAST
      # these keys, all booleans — they MAY add caps their own modules gate
      # on (superset contract; validating extra caps is the wrapper's job).
      canonicalCapKeys = builtins.attrNames machines.personal-mac.caps;
      capsOk =
        caps:
        builtins.all (k: caps ? ${k} && builtins.isBool caps.${k}) canonicalCapKeys
        && builtins.all (k: builtins.isBool caps.${k}) (builtins.attrNames caps);

      # One host = one row of the capability table. All per-host variance flows
      # from `caps`/`identity` through specialArgs + extraSpecialArgs — modules
      # never branch on hostName. External wrappers compose via the optional
      # extraDarwinModules / extraHomeModules row attrs (LOCKED contract,
      # docs/external-overlays.md).
      mkHost =
        hostName: host:
        assert host ? system && host ? user && host ? identity && host ? caps;
        assert capsOk host.caps;
        let
          # Identical payload for darwin (specialArgs) and home-manager
          # (extraSpecialArgs) modules — the locked specialArgs contract.
          args = {
            inherit inputs hostName;
            inherit (host) user caps identity;
          };
          extraDarwin = host.extraDarwinModules or [ ];
          extraHome = host.extraHomeModules or [ ];
          configurationRevision = host.configurationRevision or (self.rev or self.dirtyRev or null);
        in
        nix-darwin.lib.darwinSystem {
          inherit (host) system;
          specialArgs = args;
          modules = [
            # hosts/${hostName}.nix only exists for in-repo hosts — an external
            # wrapper's host row references its own shim, so fall back to the
            # darwin module set directly when no in-repo shim exists.
            (
              if builtins.pathExists ./hosts/${hostName}.nix then
                ./hosts/${hostName}.nix
              else
                { imports = [ ./modules/darwin ]; }
            )
            home-manager.darwinModules.home-manager
            {
              # Internal hosts inherit this repo's revision. External wrappers
              # pass their own revision in the host row; mkDefault also lets an
              # extra Darwin module supply it without an option conflict.
              system.configurationRevision = nixpkgs.lib.mkDefault configurationRevision;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                # home-manager's checkLinkTargets aborts the WHOLE activation on
                # the first pre-existing unmanaged file at any target path. On a
                # box still carrying files from a previous (non-nix) dotfile
                # manager that is every target, so the first switch can never
                # succeed without this. With it, each colliding file is renamed
                # to <target>.chezmoi-bak and activation proceeds.
                #
                # NOT durable rollback material. The pinned home-manager's
                # backup step is `mv "$target" "$target.$ext"` with no -n, and it
                # only `rm`s a pre-existing backup when HOME_MANAGER_BACKUP_
                # OVERWRITE is set (nothing here sets it). So a SECOND collision
                # at the same target silently overwrites the first backup — if a
                # real file reappears at a managed path and you switch again, the
                # original pre-nix content is gone. Copy anything you actually
                # care about out of band before the first switch.
                backupFileExtension = "chezmoi-bak";
                extraSpecialArgs = args;
                sharedModules = extraHome;
                users.${host.user} = import ./modules/home;
              };
            }
          ]
          ++ extraDarwin;
        };
    in
    {
      darwinConfigurations = builtins.mapAttrs mkHost machines;

      # `nix flake check` does not recognize darwinConfigurations as a standard
      # deeply-evaluated output. Export every host's system closure through
      # checks so evaluation must reach config.system.build.toplevel, and a full
      # check can realize the exact closure that darwin-rebuild will activate.
      checks = nixpkgs.lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # Same package as home.packages (fastMovingPackages): 26.05's
          # statix fails checkPhase on this pin; see modules/home/packages.nix.
          statixPkg = nixpkgs-unstable.legacyPackages.${system}.statix;
          hostChecks = builtins.mapAttrs (
            hostName: _host: self.darwinConfigurations.${hostName}.config.system.build.toplevel
          ) (nixpkgs.lib.filterAttrs (_: host: host.system == system) machines);
        in
        hostChecks
        // {
          statix = pkgs.runCommand "statix-check" { nativeBuildInputs = [ statixPkg ]; } ''
            statix check ${self}
            touch "$out"
          '';
        }
      );

      # One canonical formatter for the whole repository. `nix fmt` selects the
      # package for the current host system.
      formatter = nixpkgs.lib.genAttrs systems (system: nixpkgs.legacyPackages.${system}.nixfmt);

      # ── Public library surface (LOCKED contract v1.0) ──────────────────
      lib = { inherit mkHost canonicalCapKeys; };
      darwinModules.default = import ./modules/darwin;
      homeModules = {
        default = import ./modules/home;
        rawDotfiles = import ./modules/home/raw-dotfiles.nix;
      };
      # Alias: some consumers spell it homeManagerModules.
      homeManagerModules = self.homeModules;
    };
}
