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

      # One host = one row of the capability table. All per-host variance flows
      # from `caps`/`identity` through specialArgs + extraSpecialArgs — modules
      # never branch on hostName. Adding a machine stays a one-row edit.
      mkHost =
        hostName: host:
        assert host ? system && host ? user && host ? identity && host ? caps;
        let
          # Identical payload for darwin (specialArgs) and home-manager
          # (extraSpecialArgs) modules — the locked specialArgs contract.
          args = {
            inherit inputs hostName;
            inherit (host) user caps identity;
          };
        in
        nix-darwin.lib.darwinSystem {
          system = host.system;
          specialArgs = args;
          modules = [
            ./hosts/${hostName}.nix
            nix-homebrew.darwinModules.nix-homebrew
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              # First switch on a machine still running chezmoi collides on every
              # target home-manager wants to symlink (chezmoi already deployed a
              # file there). Back the pre-existing file up to <name>.chezmoi-bak
              # instead of aborting activation; these backups double as rollback
              # material for the m5 trial cutover.
              home-manager.backupFileExtension = "chezmoi-bak";
              home-manager.extraSpecialArgs = args;
              home-manager.users.${host.user} = import ./modules/home;
            }
          ];
        };
    in
    {
      darwinConfigurations = builtins.mapAttrs mkHost machines;
    };
}
