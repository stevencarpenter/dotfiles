{
  pkgs,
  lib,
  caps,
  identity,
  user,
  ...
}:

# Nix declares packages in an independent Homebrew install at /opt/homebrew.
# Bootstrap installs brew before the first switch. Native macOS tools, GUI apps,
# selected fonts, and shell binaries stay here; Nix CLI packages use packages.nix.
let
  isAarch64 = pkgs.stdenv.hostPlatform.isAarch64;
in
{
  homebrew = {
    enable = true;

    # Manual brew commands are deterministic too: updates happen only through
    # the explicit `just brew-upgrade` maintenance workflow.
    global.autoUpdate = false;

    onActivation = {
      # Rebuilds install missing packages; upgrades require `just brew-upgrade`.
      autoUpdate = false;
      upgrade = false;

      # Preserve unmanaged packages. `just brew-audit` reports drift for review.
      # Never use cleanup = "zap"; it removes application data.
      cleanup = "none";

      extraEnv = {
        HOMEBREW_NO_ANALYTICS = "1";
        HOMEBREW_NO_ENV_HINTS = "1";
        HOMEBREW_NO_UPDATE_REPORT_NEW = "1";
      };
    };

    # Render the Brewfile to a stable global location.
    global.brewfile = true;

    taps = [
      # Ungated: carries `crush`, declared in brews below (rationale there).
      "charmbracelet/tap"
    ]
    ++ lib.optionals caps.tiling [
      "nikitabobko/tap"
      "FelixKratz/formulae"
    ];

    brews = [
      # Shell binaries: kept in Homebrew because dot_config/zsh/.zshrc probes
      # the Homebrew prefix for zsh and the completion paths assume it.
      "zsh"
      "zsh-completions"
      "bash"
      "bash-completion"
      # GNU `watch` (procps) has spotty Darwin packaging in nixpkgs: kept
      # brew to preserve current behavior.
      "watch"
      # Git worktree helper; not confirmed in nixpkgs: kept brew.
      "worktrunk"
      # No nixpkgs equivalent; both are homebrew/core formulae.
      "herdr"
      "mole"
      # Crush's FSL-1.1 license prevents Hydra caching, requiring local Nix builds.
      # Homebrew 6 requires formula-level trust and a fully qualified tap name.
      {
        name = "charmbracelet/tap/crush";
        trusted = true;
      }
      # OrbStack supplies Docker CLI completions.
    ]
    # mactop requires Apple Silicon.
    ++ lib.optionals isAarch64 [ "mactop" ]
    # brew services supervises tailscaled; nix-darwin has no services.tailscale.
    # Match the non-work tailscale.zsh gate in dotfiles.nix.
    ++ lib.optionals (identity != "work") [ "tailscale" ]
    ++ lib.optionals caps.tiling [
      # Homebrew 6 requires explicit trust for third-party tap code. Keep
      # this scoped to the two formulae we install rather than trusting the
      # entire FelixKratz tap. Fully-qualified names are required for
      # formula-level `trusted = true` to take effect in Brewfile evaluation.
      {
        name = "felixkratz/formulae/sketchybar";
        trusted = true;
      }
      {
        name = "felixkratz/formulae/borders";
        trusted = true;
      }
    ]
    ++ lib.optionals caps.dev [
      # Homebrew supplies newer Railway releases than the soaked unstable pin.
      # At the 2026-08-07 comparison: Nix 5.27.0, Homebrew 5.31.0.
      "railway"
      # Keep Homebrew bottles until `nix build --dry-run` confirms Darwin cache
      # coverage; uncached Swift builds can take hours.
      "swiftlint"
      "swiftformat"
      "swift-format"
      "xcbeautify"
    ];

    casks = [
      # `op`: kept brew to pair its update/signing cadence with the
      # 1Password.app GUI cask for consistent biometric/keychain integration.
      "1password-cli"
    ]
    ++ lib.optionals caps.gui [
      "ghostty"
      "raycast"
      "1password"
      "bbedit"
      "obsidian"
      "orbstack"
      "codex"
      "handy"
      # Bespoke Powerlevel10k-patched Meslo build: not a standard nixpkgs
      # font, stays a cask.
      "font-meslo-for-powerlevel10k"
    ]
    # aerospace is a third-party tap cask with no nixpkgs equivalent.
    ++ lib.optionals caps.tiling [
      "nikitabobko/tap/aerospace"
    ]
    # SketchyBar icon font requires both GUI and tiling.
    ++ lib.optionals (caps.gui && caps.tiling) [
      "font-sketchybar-app-font"
    ]
    # Homebrew supplies fonts without confirmed Nix cache coverage.
    ++ lib.optionals caps.dev [
      "font-input"
      "font-intel-one-mono"
      "font-iosevka"
      "font-inconsolata-go-nerd-font"
    ];
  };

  # Restore brew's completion symlink only when source and destination directory
  # exist, avoiding a dangling link on a fresh install.
  system.activationScripts.postActivation.text = lib.mkAfter (
    ''
      _brew_completion_src="/opt/homebrew/completions/zsh/_brew"
      _brew_completion_dir="/opt/homebrew/share/zsh/site-functions"
      if [ -e "$_brew_completion_src" ] && [ -d "$_brew_completion_dir" ]; then
        ln -sfn \
          "$_brew_completion_src" \
          "$_brew_completion_dir/_brew"
      fi
    ''
    + lib.optionalString caps.tiling ''
      # Pin third-party formulae after installation. Activation phases can overlap,
      # so retry each formula separately. Run brew as the user, with no SUDO_* flags.
      # Pin failures warn without aborting the switch.
      if [ -x /opt/homebrew/bin/brew ]; then
        _brew_as_user() {
          /usr/bin/sudo -H -u ${user} \
            /usr/bin/env -u SUDO_USER -u SUDO_UID -u SUDO_GID -u SUDO_COMMAND \
            /opt/homebrew/bin/brew "$@"
        }
        _brew_pinned_dir="/opt/homebrew/var/homebrew/pinned"

        for _brew_formula in sketchybar borders; do
          # Existing pin symlinks need no brew invocation.
          if [ -L "$_brew_pinned_dir/$_brew_formula" ]; then
            continue
          fi

          _brew_installed=0
          _brew_pinned=0
          for _brew_attempt in 1 2 3 4 5; do
            if _brew_as_user list --formula "$_brew_formula" >/dev/null 2>&1; then
              _brew_installed=1
              if _brew_as_user pin "$_brew_formula" >/dev/null 2>&1; then
                _brew_pinned=1
              fi
              break
            fi
            /bin/sleep 2
          done

          # Homebrew may report an already-converged pin as a warning. The
          # filesystem link is the authoritative pin state either way.
          if [ -L "$_brew_pinned_dir/$_brew_formula" ]; then
            _brew_pinned=1
          fi
          if [ "$_brew_pinned" -ne 1 ]; then
            if [ "$_brew_installed" -eq 1 ]; then
              echo "warning: $_brew_formula is installed but Homebrew could not pin it" >&2
            else
              echo "warning: $_brew_formula was not installed after Homebrew activation" >&2
            fi
          fi
        done
      fi
    ''
  );
}
