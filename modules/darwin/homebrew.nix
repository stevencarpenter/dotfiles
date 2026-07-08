{ config, pkgs, lib, caps, user, ... }:

# Homebrew management via nix-homebrew (installs/owns the brew prefix) plus
# nix-darwin's `homebrew` module (declares taps/brews/casks, replacing the old
# dot_config/homebrew/Brewfile.tmpl). Only GUI apps, macOS-native tooling with
# no nixpkgs equivalent, bespoke fonts, and shell binaries the zshrc probes at
# the Homebrew prefix stay here; pure CLI tools moved to home.packages (see
# modules/home/packages.nix).
#
# Capability gating mirrors the Brewfile's template blocks:
#   tiling  → WM/status-bar tap+brew+cask stack
#   gui     → GUI casks + GUI fonts
#   dev     → railway CLI + dev-flavored font casks
#   identity == "work" → conftest
let
  isAarch64 = pkgs.stdenv.hostPlatform.isAarch64;
in
{
  nix-homebrew = {
    enable = true;
    user = user;
    # Manage an Intel (x86) brew prefix alongside the native one only on Apple
    # Silicon; meaningless (and rejected) on an x86_64 host like lab-mac.
    enableRosetta = isAarch64;
    # Adopt an existing Homebrew install rather than failing if one is present.
    autoMigrate = true;
    # Leave taps mutable (brew taps them at runtime from homebrew.taps) instead
    # of pinning homebrew-core/cask as flake inputs — keeps the flake thin.
    # mutableTaps stays at its default (true).
  };

  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      upgrade = false;
      # GRADUATION: start conservative. "none" leaves anything not listed here
      # in place (safe during the nix cutover while the brew inventory is still
      # being audited). Move to "uninstall" once the lists below are confirmed
      # complete. NEVER use "zap" — it deletes app data/config, not just the app.
      cleanup = "none";
    };

    # Render the Brewfile to a stable global location.
    global.brewfile = true;

    taps =
      lib.optionals caps.tiling [
        "nikitabobko/tap"
        "FelixKratz/formulae"
      ];

    brews =
      [
        # Shell binaries: kept in Homebrew because dot_config/zsh/.zshrc probes
        # the Homebrew prefix for zsh and the completion paths assume it.
        "zsh"
        "zsh-completions"
        "bash"
        "bash-completion"
        # GNU `watch` (procps) has spotty Darwin packaging in nixpkgs — kept
        # brew to preserve current behavior.
        "watch"
        # Git worktree helper; not confirmed in nixpkgs — kept brew.
        "worktrunk"
        # NOTE: `docker-completion` from the old Brewfile is dropped — OrbStack
        # (gui cask below) ships the docker CLI + its shell completions.
      ]
      # mactop is a macOS-native (Apple Silicon) power monitor — only builds/
      # makes sense on aarch64; omitted on the Intel lab-mac.
      ++ lib.optionals isAarch64 [ "mactop" ]
      ++ lib.optionals caps.tiling [
        "sketchybar"
        "borders"
      ]
      ++ lib.optionals caps.dev [
        # railway CLI: fast-moving vendor tool, nixpkgs lags — kept brew.
        "railway"
      ];
      # NOTE: the Brewfile's work-only `conftest` moved to nixpkgs — see the
      # identity=="work" gate in modules/home/packages.nix (SME split).

    casks =
      [
        # `op` — kept brew to pair its update/signing cadence with the
        # 1Password.app GUI cask for consistent biometric/keychain integration.
        "1password-cli"
      ]
      ++ lib.optionals caps.gui [
        "alt-tab"
        "ghostty"
        "raycast"
        "visual-studio-code"
        "1password"
        "bbedit"
        "obsidian"
        "orbstack"
        "the-unarchiver"
        "codex"
        # Bespoke Powerlevel10k-patched Meslo build — not a standard nixpkgs
        # font, stays a cask.
        "font-meslo-for-powerlevel10k"
      ]
      # aerospace is a third-party tap cask with no nixpkgs equivalent.
      ++ lib.optionals caps.tiling [
        "nikitabobko/tap/aerospace"
      ]
      # FelixKratz's custom sketchybar icon font — gui AND tiling in the
      # original (nested gate).
      ++ lib.optionals (caps.gui && caps.tiling) [
        "font-sketchybar-app-font"
      ]
      # Dev-flavored fonts NOT confidently available (or too heavy to build,
      # e.g. iosevka) in nixpkgs are kept as dev-gated casks. The
      # high-confidence subset moved to home.packages fonts. Together these two
      # sets cover every font from the Brewfile's dev block with none dropped.
      ++ lib.optionals caps.dev [
        "font-anonymous-pro"
        "font-bebas-neue"
        "font-courier-prime"
        "font-ia-writer-duo"
        "font-ia-writer-mono"
        "font-ia-writer-quattro"
        "font-input"
        "font-intel-one-mono"
        "font-iosevka"
        "font-red-hat-mono"
        "font-ubuntu-mono"
        "font-inconsolata-go-nerd-font"
      ];
  };
}
