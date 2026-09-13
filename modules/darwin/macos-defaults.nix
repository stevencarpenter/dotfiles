{
  config,
  pkgs,
  lib,
  user,
  ...
}:

# macOS preferences use typed options or CustomUserPreferences for unsupported keys.
# Activation creates the screenshot directory and Spotlight exclusion sentinels.
{
  system.defaults = {
    # ─── 1. General / UI (NSGlobalDomain) ─────────────────────────────────
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      NSAutomaticCapitalizationEnabled = true;
      NSAutomaticPeriodSubstitutionEnabled = true;
      "com.apple.trackpad.scaling" = 1.5;
    };

    # ─── 2. Dock ──────────────────────────────────────────────────────────
    dock = {
      autohide = true;
      autohide-delay = 1.0;
      autohide-time-modifier = 0.6;
      orientation = "left";
      tilesize = 40;
      # Bottom right: Quick Note (14). Top right: Lock Screen (13).
      # Modifier keys use CustomUserPreferences below.
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
      # NOTE: `ShowSidebar` is handled via CustomUserPreferences below: it is
      # not a confirmed typed key in nix-darwin's finder submodule.
    };

    # ─── 4. Screenshots ───────────────────────────────────────────────────
    screencapture = {
      # nix-darwin does not create the directory; see activation snippet below.
      location = "/Users/${user}/Desktop/screenshots";
      show-thumbnail = false;
    };

    # ─── 5. Menu bar clock ────────────────────────────────────────────────
    menuExtraClock = {
      # 0 = never show the date.
      ShowDate = 0;
      ShowDayOfWeek = true;
    };

    # ─── 6. Trackpad (internal, com.apple.AppleMultitouchTrackpad) ─────────
    trackpad = {
      Clicking = false;
      TrackpadThreeFingerDrag = false;
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
      "com.apple.finder" = {
        ShowSidebar = true;
      };
      # The typed trackpad module targets the internal device only.
      # Apply the same settings to paired Bluetooth trackpads.
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
