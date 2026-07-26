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

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    # Escape hatch for tools whose upstream release cadence outruns the stable
    # channel's backport window — the allowlist lives in
    # modules/home/packages.nix. Deliberately does NOT set
    # `inputs.nixpkgs.follows`: tracking a different channel is the entire
    # point, and unlike nix-darwin/home-manager/agenix this input has no
    # nixpkgs input of its own — it IS nixpkgs.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      nix-homebrew,
      agenix,
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
            nix-homebrew.darwinModules.nix-homebrew
            home-manager.darwinModules.home-manager
            {
              # Internal hosts inherit this repo's revision. External wrappers
              # pass their own revision in the host row; mkDefault also lets an
              # extra Darwin module supply it without an option conflict.
              system.configurationRevision = nixpkgs.lib.mkDefault configurationRevision;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
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
          hostChecks = builtins.mapAttrs (
            hostName: _host: self.darwinConfigurations.${hostName}.config.system.build.toplevel
          ) (nixpkgs.lib.filterAttrs (_: host: host.system == system) machines);
        in
        hostChecks
        // {
          statix = pkgs.runCommand "statix-check" { nativeBuildInputs = [ pkgs.statix ]; } ''
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
