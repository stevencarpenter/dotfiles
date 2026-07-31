{
  config,
  pkgs,
  lib,
  caps,
  identity,
  user,
  ...
}:

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
#   dev     → railway CLI + Swift toolchain + dev-flavored font casks
#   identity != "work" → tailscale (homelab access; matches the tailscale.zsh
#                        profile.d gate in modules/home/dotfiles.nix)
let
  isAarch64 = pkgs.stdenv.hostPlatform.isAarch64;
in
{
  nix-homebrew = {
    enable = true;
    inherit user;
    # Manage an Intel (x86) brew prefix alongside the native one only on Apple
    # Silicon; meaningless (and rejected) on a native x86_64 host. Both current
    # machines are aarch64, so this is a defensive guard for any future Intel box.
    enableRosetta = isAarch64;
    # Adopt an existing Homebrew install rather than failing if one is present.
    autoMigrate = true;
    # Leave taps mutable (brew taps them at runtime from homebrew.taps) instead
    # of pinning homebrew-core/cask as flake inputs — keeps the flake thin.
    # mutableTaps stays at its default (true).
  };

  homebrew = {
    enable = true;

    # Manual brew commands are deterministic too: updates happen only through
    # the explicit `just brew-upgrade` maintenance workflow.
    global.autoUpdate = false;

    onActivation = {
      # A rebuild must be idempotent: it installs missing declarations but never
      # turns a locked Nix generation into an implicit rolling Homebrew upgrade.
      autoUpdate = false;
      upgrade = false;

      # Keep unmanaged formulae/casks in place. `cleanup = "check"` aborts
      # activation when any exist, and this machine still has reviewed-useful
      # legacy inventory. `just brew-audit` is the explicit drift report;
      # destructive cleanup remains a reviewed operator action. NEVER use
      # "zap" here; it removes application data.
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
      # GNU `watch` (procps) has spotty Darwin packaging in nixpkgs — kept
      # brew to preserve current behavior.
      "watch"
      # Git worktree helper; not confirmed in nixpkgs — kept brew.
      "worktrunk"
      # No nixpkgs equivalent; both are homebrew/core formulae.
      "herdr"
      "mole"
      # charmbracelet/tap/crush. nixpkgs DOES package `crush`, but the flake
      # tracks stable 26.05 while upstream ships roughly every four days, so
      # the nix attr trails by months — the same trade that keeps `railway` a
      # brew. Fully-qualified + `trusted` because Homebrew 6 requires explicit
      # trust for third-party tap code (see the sketchybar/borders block).
      {
        name = "charmbracelet/tap/crush";
        trusted = true;
      }
      # NOTE: `docker-completion` from the old Brewfile is dropped — OrbStack
      # (gui cask below) ships the docker CLI + its shell completions.
      #
      # NOTE: `archon` (coleam00/archon) is deliberately NOT declared — it is
      # being retired from this machine rather than adopted.
    ]
    # mactop is a macOS-native (Apple Silicon) power monitor — only builds/
    # makes sense on aarch64 (guard is defensive; both current hosts qualify).
    ++ lib.optionals isAarch64 [ "mactop" ]
    # Homelab access runs over Tailscale on non-work machines. Kept in Homebrew
    # rather than nixpkgs on purpose: nixpkgs ships the binaries only, and
    # nix-darwin has no `services.tailscale` (that option is NixOS-only), so
    # `brew services` remains what actually supervises tailscaled. Mirrors the
    # `identity != "work"` gate on profile.d/tailscale.zsh in dotfiles.nix.
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
      # railway CLI: fast-moving vendor tool, nixpkgs lags — kept brew.
      "railway"
      # Swift toolchain. These four DO exist in the locked nixpkgs, but
      # available != cached: a Swift build on aarch64-darwin can turn a switch
      # into a multi-hour source compile, the same hazard that keeps iosevka a
      # cask. Homebrew ships bottles. Promote to home.packages individually
      # only once `nix build --dry-run` reports one under "will be fetched".
      "swiftlint"
      "swiftformat"
      "swift-format"
      "xcbeautify"
    ];
    # NOTE: `conftest` moved to nixpkgs — see the work-only condition in
    # modules/home/packages.nix.

    casks = [
      # `op` — kept brew to pair its update/signing cadence with the
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
      "alt-tab"
      "handy"
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
      "font-input"
      "font-intel-one-mono"
      "font-iosevka"
      "font-inconsolata-go-nerd-font"
    ];
  };

  # nix-homebrew replaces Homebrew's mutable repository with a nix-store
  # source. Its first auto-migration can leave the old core `_brew` completion
  # symlink pointing at the removed `/opt/homebrew/completions` directory.
  # Re-anchor that link to the pinned Homebrew source on every activation.
  system.activationScripts.postActivation.text = lib.mkAfter (
    ''
      _brew_completion_dir="/opt/homebrew/share/zsh/site-functions"
      if [ -d "$_brew_completion_dir" ]; then
        ln -sfn \
          "${config.nix-homebrew.package}/completions/zsh/_brew" \
          "$_brew_completion_dir/_brew"
      fi
    ''
    + lib.optionalString caps.tiling ''
      # Converge the third-party-tap pin policy (see onActivation comment).
      # Pin state is imperative brew metadata; re-asserting it every switch means
      # a fresh machine self-heals after its first bundle run. Homebrew activation
      # and Home Manager activation can overlap on a first run, so wait briefly
      # for each formula and pin them independently. Runs as root, and brew
      # refuses root, so drop to the owning user with a clean user environment.
      # Warn-never-fail.
      if [ -x /opt/homebrew/bin/brew ]; then
        _brew_as_user() {
          /usr/bin/sudo -H -u ${user} \
            /usr/bin/env -u SUDO_USER -u SUDO_UID -u SUDO_GID -u SUDO_COMMAND \
            /opt/homebrew/bin/brew "$@"
        }
        _brew_pinned_dir="/opt/homebrew/var/homebrew/pinned"

        for _brew_formula in sketchybar borders; do
          # `brew pin` is already converged when this symlink exists. Recognize
          # that state directly so every later rebuild is quiet and idempotent.
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
