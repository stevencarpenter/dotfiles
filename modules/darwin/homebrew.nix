{
  pkgs,
  lib,
  caps,
  identity,
  user,
  ...
}:

# Declarative Homebrew via nix-darwin's `homebrew` module (taps/brews/casks,
# replacing the old dot_config/homebrew/Brewfile.tmpl). Homebrew ITSELF is an
# independent, self-updating install at /opt/homebrew (and /usr/local for the
# Rosetta prefix) — nix references that install but does not own it. This
# replaced nix-homebrew (zhaofengli), whose brew-src pin froze brew at a
# patched 6.0.1 while homebrew-core moved on (gcc 16.1's
# `configure_gcc_runtime` post-install step broke installs). Bootstrap of a
# fresh machine installs brew via the official installer BEFORE the first
# darwin-rebuild switch.
# Only GUI apps, macOS-native tooling with no nixpkgs equivalent, bespoke
# fonts, and shell binaries the zshrc probes at the Homebrew prefix stay
# here; pure CLI tools moved to home.packages (see modules/home/packages.nix).
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
      # charmbracelet/tap/crush. Stays brew, but NOT for the reason this comment
      # used to give ("the flake tracks stable 26.05, so the nix attr trails by
      # months"). That reasoning is obsolete: `fastMovingPackages` in
      # modules/home/packages.nix now takes named packages from
      # nixpkgs-unstable, which is the escape hatch that argument called for.
      #
      # Re-evaluated 2026-08-07 against nixpkgs-unstable @ the pinned rev, and
      # the real blockers are different ones:
      #   - crush is UNFREE in nixpkgs (FSL-1.1-MIT, meta.license.free = false),
      #     so promoting it means an allowUnfree carve-out on the pkgsFresh
      #     instantiation, which today deliberately sets no nixpkgs.config at all.
      #   - Unfree means Hydra does not build it, so there is no binary cache
      #     entry (narinfo 404 — verified, not assumed). Every bump would be a
      #     local source build.
      #   - The pinned rev carries 0.86.0 (2026-07-20) against 0.88.0 installed,
      #     so the move is an immediate downgrade of an actively-used tool.
      # Brew also keeps it inside `just brew-upgrade`, which is where the
      # AI-harness tools are meant to stay current.
      #
      # Fully-qualified + `trusted` because Homebrew 6 requires explicit trust
      # for third-party tap code (see the sketchybar/borders block).
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
      # railway CLI: kept brew, but this is a cadence trade, not an availability
      # one — nixpkgs does package it, free and cached (narinfo 200, verified
      # 2026-08-07). Promoting it to `fastMovingPackages` would work; it was
      # measured and declined. At the pinned unstable rev the attr is 5.27.0
      # (2026-07-17) against 5.31.0 from brew, and the 7-day soak window on that
      # input (see flake.nix) puts steady state ~3-4 weeks behind. That is the
      # whole cost — the upside would have been a lockfile-pinned version rather
      # than whatever each machine last resolved. Revisit if the lag matters more
      # than the currency.
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

  # The independent brew install keeps its zsh completion at
  # completions/zsh/_brew (prefix-relative); the installer normally links it
  # into share/zsh/site-functions. Re-anchor that link on every activation so
  # a fresh prefix self-heals even if the link was lost (this replaced the
  # nix-homebrew migration that left the link dangling). Both sides are
  # existence-checked: ln -sfn would happily create a dangling link.
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
