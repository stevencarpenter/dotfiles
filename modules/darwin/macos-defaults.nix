{ config, pkgs, lib, user, ... }:

# Declarative port of .chezmoiscripts/darwin/run_onchange_configure-macos-defaults.sh.
# Each `defaults write` maps to a typed system.defaults.* option where one
# exists, else to system.defaults.CustomUserPreferences.<domain>. The two
# non-defaults side effects (screenshots dir, Spotlight sentinels) become a
# small activation snippet. The original script's trailing `killall` is dropped:
# nix-darwin runs `activateSettings -u` after writing defaults, which refreshes
# the affected agents. If a reviewer finds a managed key not taking effect until
# logout on the pinned release, re-add a killall of Dock/Finder/SystemUIServer
# to system.activationScripts.postActivation.text.
#
# Original commands are quoted in comments next to any mapping that is not an
# obvious 1:1, or that the phase-1 SME flagged for release verification.
{
  system.defaults = {
    # ─── 1. General / UI (NSGlobalDomain) ─────────────────────────────────
    NSGlobalDomain = {
      # defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"
      AppleInterfaceStyle = "Dark";
      # defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
      ApplePressAndHoldEnabled = false;
      # defaults write NSGlobalDomain InitialKeyRepeat -int 15
      InitialKeyRepeat = 15;
      # defaults write NSGlobalDomain KeyRepeat -int 2
      KeyRepeat = 2;
      # defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool true
      NSAutomaticCapitalizationEnabled = true;
      # defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool true
      NSAutomaticPeriodSubstitutionEnabled = true;
      # defaults write NSGlobalDomain com.apple.trackpad.scaling -float 1.5
      "com.apple.trackpad.scaling" = 1.5;
    };

    # ─── 2. Dock ──────────────────────────────────────────────────────────
    dock = {
      autohide = true;
      # defaults write com.apple.dock autohide-delay -float 1.0
      autohide-delay = 1.0;
      # defaults write com.apple.dock autohide-time-modifier -float 0.6
      autohide-time-modifier = 0.6;
      orientation = "left";
      tilesize = 40;
      # Hot corners: br = Quick Note (14), tr = Lock Screen (13). The
      # `wvous-*-modifier` keys are not typed nix-darwin options; the
      # modifier defaults to 0 (none), matching the original script, and is
      # written via CustomUserPreferences."com.apple.dock" below.
      wvous-br-corner = 14;
      wvous-tr-corner = 13;
    };

    # ─── 3. Finder ────────────────────────────────────────────────────────
    finder = {
      # Nlsv = list view.
      FXPreferredViewStyle = "Nlsv";
      ShowHardDrivesOnDesktop = false;
      ShowExternalHardDrivesOnDesktop = true;
      ShowRemovableMediaOnDesktop = true;
      # NOTE: `ShowSidebar` is handled via CustomUserPreferences below — it is
      # not a confirmed typed key in nix-darwin's finder submodule.
    };

    # ─── 4. Screenshots ───────────────────────────────────────────────────
    screencapture = {
      # defaults write com.apple.screencapture location -string "$HOME/Desktop/screenshots"
      # nix-darwin does not create the directory; see activation snippet below.
      location = "/Users/${user}/Desktop/screenshots";
      # defaults write com.apple.screencapture show-thumbnail -bool false
      show-thumbnail = false;
    };

    # ─── 5. Menu bar clock ────────────────────────────────────────────────
    menuExtraClock = {
      # Original: `defaults write com.apple.menuextra.clock ShowDate -int 0`.
      # NOTE (SME flag): some nix-darwin releases type ShowDate as a string
      # enum ("0"|"1"|"2") rather than the raw int. If the build rejects `0`,
      # use "0" (0 = never show date). A wrong value here is silent, not a
      # build error — verify the written plist after switch.
      ShowDate = 0;
      ShowDayOfWeek = true;
    };

    # ─── 6. Trackpad (internal, com.apple.AppleMultitouchTrackpad) ─────────
    trackpad = {
      # defaults write com.apple.AppleMultitouchTrackpad Clicking -bool false
      Clicking = false;
      # defaults write ... TrackpadThreeFingerDrag -bool false
      TrackpadThreeFingerDrag = false;
      # NOTE (SME flag): the four-finger swipe gesture keys are not exposed by
      # every nix-darwin trackpad submodule release. If the build rejects
      # these two, move them into the CustomUserPreferences internal-trackpad
      # block below alongside the Bluetooth-domain copies.
      TrackpadFourFingerHorizSwipeGesture = 2;
      TrackpadFourFingerVertSwipeGesture = 2;
    };

    # ─── 7. Activity Monitor ──────────────────────────────────────────────
    ActivityMonitor = {
      # 100 = All Processes.
      ShowCategory = 100;
    };

    # ─── Fallbacks with no typed nix-darwin option ────────────────────────
    CustomUserPreferences = {
      # Hot-corner modifier keys (no typed option; see dock block above).
      "com.apple.dock" = {
        wvous-br-modifier = 0;
        wvous-tr-modifier = 0;
      };
      # Finder ShowSidebar has no confirmed typed option.
      # defaults write com.apple.finder ShowSidebar -bool true
      "com.apple.finder" = {
        ShowSidebar = true;
      };
      # Bluetooth (paired) trackpad domain has NO nix-darwin equivalent — the
      # trackpad submodule only ever targets the internal multitouch domain.
      # These duplicate the internal-trackpad values for a paired BT trackpad.
      # defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad <key> …
      "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
        Clicking = false;
        TrackpadThreeFingerDrag = false;
        TrackpadFourFingerHorizSwipeGesture = 2;
        TrackpadFourFingerVertSwipeGesture = 2;
      };
    };
  };

  # ─── 8. Filesystem side effects (not `defaults write`) ──────────────────
  # Screenshots target dir + Spotlight `.metadata_never_index` sentinels for
  # high-churn dev trees. Activation runs as root, so paths are absolute under
  # the user's home and ownership is handed back to the user. Idempotent.
  system.activationScripts.postActivation.text = ''
    # --- macOS defaults: screenshots dir + Spotlight exclusion sentinels ---
    mkdir -p "/Users/${user}/Desktop/screenshots"
    chown ${user}:staff "/Users/${user}/Desktop/screenshots" || true
    for _d in "/Users/${user}/projects" "/Users/${user}/programs"; do
      mkdir -p "$_d"
      touch "$_d/.metadata_never_index"
      chown ${user}:staff "$_d" "$_d/.metadata_never_index" || true
    done
  '';
}
