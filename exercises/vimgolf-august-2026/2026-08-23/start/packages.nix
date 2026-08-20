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
    ripgrep

    # Language runtimes
    go
    lua
    nodejs
    python313
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
    bat
  ];
}
