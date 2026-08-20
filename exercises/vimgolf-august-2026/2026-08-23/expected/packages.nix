{ pkgs, ... }:
{
  home.packages = with pkgs; [
    alejandra
    curl
    fd
    git
    jq
    just
    nil
    nix-tree
    ripgrep-all

    # Language runtimes
    go
    lua
    nodejs
    python314
    rustup

    # Interactive tools
    atuin
    bat
    bottom
    delta
    dust
    eza
    fzf
    glow
    hyperfine
    lazygit
    procs
    sd
    television
    tree
    yazi
    zoxide

    # Replace this final package, not the earlier one.
    btop
  ];
}
