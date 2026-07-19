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

    onActivation = {
      # autoUpdate/upgrade stay ON deliberately: rebuild-time brew churn exists
      # to track fast-moving tools (codex, worktrunk, railway, 1password-cli).
      # The slow-moving third-party WM tap stack is carved OUT of that firehose
      # instead: sketchybar + borders are `brew pin`ed by the postActivation
      # snippet below, so upgrading tap code is a deliberate
      # `brew upgrade sketchybar borders` (after `brew unpin`), not a side
      # effect of every switch. aerospace (tap *cask*) has no pin mechanism in
      # Homebrew — it remains auto-upgraded; accepted residual supply-chain
      # exposure, revisit if nikitabobko/tap ever changes hands.
      autoUpdate = true;
      upgrade = true;
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
      # makes sense on aarch64 (guard is defensive; both current hosts qualify).
      ++ lib.optionals isAarch64 [ "mactop" ]
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
        "ghostty"
        "raycast"
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
  system.activationScripts.postActivation.text = lib.mkAfter (''
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
    # refuses root, so drop to the owning user. Warn-never-fail.
    if [ -x /opt/homebrew/bin/brew ]; then
      for _brew_formula in sketchybar borders; do
        _brew_pinned=0
        for _brew_attempt in 1 2 3 4 5; do
          if /usr/bin/sudo -u ${user} /opt/homebrew/bin/brew list --formula "$_brew_formula" \
            >/dev/null 2>&1; then
            if /usr/bin/sudo -u ${user} /opt/homebrew/bin/brew pin "$_brew_formula" \
              >/dev/null 2>&1; then
              _brew_pinned=1
            fi
            break
          fi
          /bin/sleep 2
        done
        if [ "$_brew_pinned" -ne 1 ]; then
          echo "warning: could not pin $_brew_formula (not installed yet?)" >&2
        fi
      done
    fi
  '');
}
