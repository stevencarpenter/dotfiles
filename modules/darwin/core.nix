{
  config,
  pkgs,
  lib,
  user,
  ...
}:

# Darwin system core: Nix daemon hardening/maintenance, primary user,
# login-shell pin, and the maxfiles launchd agent. Everything per-machine flows
# in through specialArgs (user); no hostname checks live here.
{
  # nix-darwin manages the Lix package, nix.conf, and launchd daemon.
  nix = {
    enable = true;
    package = pkgs.lix;

    # darwin-rebuild --flake needs both features; nix-darwin leaves them off by default.
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Lix sandbox setup currently fails on macOS 27 before a derivation starts
    # (`invalid errno value #45`). Keep this explicit instead of inheriting an
    # installer-dependent default. Re-enable only after the Darwin sandbox
    # compatibility bug is fixed and a full system closure builds successfully.
    settings.sandbox = false;

    # Keep 30 days of rollbacks. Separate GC and optimisation to avoid store-lock contention.
    gc = {
      automatic = true;
      interval = {
        Weekday = 7;
        Hour = 3;
        Minute = 15;
      };
      options = "--delete-older-than 30d";
    };
    optimise = {
      automatic = true;
      interval = {
        Weekday = 7;
        Hour = 4;
        Minute = 15;
      };
    };
  };

  # Keep the existing admin account out of knownUsers. postActivation sets its
  # login shell to /bin/zsh; versioned Nix or Homebrew paths can vanish on upgrade.
  users.users.${user}.home = "/Users/${user}";

  # /bin/zsh is already in /etc/shells; keep pkgs.zsh registered too so a
  # store zsh remains a valid `chsh` choice without being the login pin.
  environment.shells = [
    pkgs.zsh
    "/bin/zsh"
  ];

  # nix-darwin ships EDITOR = mkDefault "nano" in its environment module and
  # exports it from /etc/zshenv ahead of z4h and every raw dotfile, so the
  # override has to live here in nix, not in the shell config.
  environment.variables.EDITOR = "nvim";

  system = {
    # Required by recent nix-darwin so user-scoped system.defaults and the
    # homebrew module know which user to act as.
    primaryUser = user;

    # Apply the login shell and clear any stale `launchctl setenv SHELL <path>`
    # override (e.g. a versioned Homebrew Cellar path that vanishes on upgrade).
    # Both operations are idempotent. Activation runs as root; launchctl work is
    # explicitly routed into the primary user's GUI domain.
    activationScripts.postActivation.text = ''
      # --- enforce Directory Services UserShell (login-shell migration) ---
      _login_shell="/bin/zsh"
      _ds_user="/Users/${user}"
      _uid="$(/usr/bin/id -u ${user} 2>/dev/null || true)"
      if [ -z "$_uid" ]; then
        echo "cannot enforce login shell: primary user ${user} does not exist" >&2
        exit 1
      fi
      _current_shell="$(/usr/bin/dscl . -read "$_ds_user" UserShell 2>/dev/null || true)"
      _current_shell="''${_current_shell#UserShell: }"
      if [ "$_current_shell" != "$_login_shell" ]; then
        echo "setting ${user} login shell: ''${_current_shell:-<unset>} -> $_login_shell"
        /usr/bin/dscl . -create "$_ds_user" UserShell "$_login_shell"
      fi

      # --- clear stale launchctl SHELL override ---
      _cur="$(/bin/launchctl asuser "$_uid" /bin/launchctl getenv SHELL 2>/dev/null || true)"
      if [ -n "$_cur" ] && [ "$_cur" != "$_login_shell" ]; then
        echo "clearing stale launchctl SHELL override ($_cur)"
        /bin/launchctl asuser "$_uid" /bin/launchctl unsetenv SHELL || true
      fi
    '';

    # Compatibility baseline, not the input release. Review migrations before changing it.
    stateVersion = 6;
  };

  # Raise the open-files limit at login; nix-darwin manages the LaunchAgent.
  launchd.user.agents.maxfiles = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/launchctl"
        "limit"
        "maxfiles"
        "65536"
        "2097152"
      ];
      RunAtLoad = true;
    };
  };
}
