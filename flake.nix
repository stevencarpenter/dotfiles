{
  description = "carpenter dotfiles: nix-darwin + home-manager, thin out-of-store wrapper";

  inputs = {
    # Keep nixpkgs, nix-darwin, and home-manager on matching stable releases.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # packages.nix selects tools from this independent unstable pin.
    # Keep an exact revision so flake update cannot bypass update-unstable.sh's
    # first-seen soak period. Commit timestamps do not establish channel age.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/02f5696b0e6097e589076d886b317b83ff0437d7"; # nixpkgs-unstable @ 2026-09-13
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
      # these keys, all booleans. They MAY add caps their own modules gate
      # on (superset contract; validating extra caps is the wrapper's job).
      canonicalCapKeys = builtins.attrNames machines.personal-mac.caps;
      capsOk =
        caps:
        builtins.all (k: caps ? ${k} && builtins.isBool caps.${k}) canonicalCapKeys
        && builtins.all (k: builtins.isBool caps.${k}) (builtins.attrNames caps);

      # One host = one row of the capability table. All per-host variance flows
      # from `caps`/`identity` through specialArgs + extraSpecialArgs. Modules
      # never branch on hostName. External wrappers compose via the optional
      # extraDarwinModules / extraHomeModules row attrs (LOCKED contract,
      # docs/external-overlays.md).
      mkHost =
        hostName: host:
        assert host ? system && host ? user && host ? identity && host ? caps;
        assert capsOk host.caps;
        let
          # Identical payload for darwin (specialArgs) and home-manager
          # (extraSpecialArgs) modules: the locked specialArgs contract.
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
            # hosts/${hostName}.nix only exists for in-repo hosts. An external
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
                # Rename conflicting unmanaged files so activation can proceed.
                # Back up valuable files separately: another collision at the same
                # path can overwrite the previous .chezmoi-bak copy.
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
