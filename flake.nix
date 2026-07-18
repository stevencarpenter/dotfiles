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
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      nix-homebrew,
      agenix,
    }:
    let
      machines = import ./lib/machines.nix;

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
        in
        nix-darwin.lib.darwinSystem {
          system = host.system;
          specialArgs = args;
          modules = [
            # hosts/${hostName}.nix only exists for in-repo hosts — an external
            # wrapper's host row references its own shim, so fall back to the
            # darwin module set directly when no in-repo shim exists.
            (if builtins.pathExists ./hosts/${hostName}.nix then ./hosts/${hostName}.nix else { imports = [ ./modules/darwin ]; })
            nix-homebrew.darwinModules.nix-homebrew
            home-manager.darwinModules.home-manager
            {
              system.configurationRevision = self.rev or self.dirtyRev or null;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              # First switch on a machine still running chezmoi collides on every
              # target home-manager wants to symlink (chezmoi already deployed a
              # file there). Back the pre-existing file up to <name>.chezmoi-bak
              # instead of aborting activation; these backups double as rollback
              # material for the m5 trial cutover.
              home-manager.backupFileExtension = "chezmoi-bak";
              home-manager.extraSpecialArgs = args;
              home-manager.sharedModules = extraHome;
              home-manager.users.${host.user} = import ./modules/home;
            }
          ]
          ++ extraDarwin;
        };
    in
    {
      darwinConfigurations = builtins.mapAttrs mkHost machines;

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
