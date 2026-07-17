{ config, pkgs, lib, user, ... }:

# Darwin system core: nix daemon ownership, unfree policy, primary user,
# login-shell pin, and the maxfiles launchd agent. Everything per-machine
# flows in through specialArgs (user); no hostname checks live here.
{
  # nix-darwin owns and manages the nix daemon (the standard model): it installs
  # the nix package into the system profile, writes /etc/nix/nix.conf from
  # `nix.settings`, and manages the launchd daemon. We run Lix as the interpreter
  # — the nix-darwin prerequisites recommend the Lix installer (it ships an
  # uninstaller; the upstream installer does not) and `nix.package = pkgs.lix` as
  # the supported way to select it. Unlike Determinate (which required
  # `nix.enable = false` and owned nix.conf itself), this hands nix.conf back to
  # nix-darwin, so the `nix.settings.*` options below are once again authoritative.
  nix.enable = true;
  nix.package = pkgs.lix;

  # nix-darwin does NOT enable flakes by default (only the Determinate installer
  # did). The whole repo is a flake and `darwin-rebuild switch --flake` needs both
  # features, so pin them here. Once nix-darwin owns /etc/nix/nix.conf this is the
  # durable source of truth, replacing whatever the Lix installer wrote at bootstrap.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Unfree needed for GUI casks' companion packages and some fonts
  # (vscode, obsidian, 1password, raycast, codex, …).
  nixpkgs.config.allowUnfree = true;

  # Required by recent nix-darwin so user-scoped system.defaults and the
  # homebrew module know which user to act as.
  system.primaryUser = user;

  # Login-shell pin (declarative replacement for the old imperative
  # run_onchange_set-login-shell.sh chsh dance). nix-darwin writes the
  # Directory Services UserShell, eliminating the bug class the script guarded
  # against (a stale Homebrew-cellar zsh path bricking login on arch change).
  #
  # The pin is the LITERAL /bin/zsh, not pkgs.zsh: the retired script existed
  # because a non-OS shell path (Homebrew cellar, and equally a nix store
  # path) can dangle across upgrades/GC and brick login — /bin/zsh is the one
  # shell Apple guarantees. Interactive shell richness comes from z4h config,
  # not the login-shell binary.
  #
  # NOTE (reviewer): setting `shell` for a macOS-created (i.e. not
  # nix-darwin-managed / knownUsers) account relies on newer nix-darwin driving
  # `dscl … UserShell` during activation. If the pinned nix-darwin release
  # refuses to touch an unmanaged user's shell, add `users.knownUsers` + a
  # `uid` for this user, or fall back to a chsh activation snippet.
  users.users.${user} = {
    name = user;
    home = "/Users/${user}";
    shell = "/bin/zsh";
  };

  # /bin/zsh is already in /etc/shells; keep pkgs.zsh registered too so a
  # store zsh remains a valid `chsh` choice without being the login pin.
  environment.shells = [ pkgs.zsh "/bin/zsh" ];

  # One-time migration cleanup carried over from the old login-shell script:
  # clear any stale `launchctl setenv SHELL <path>` override (e.g. a versioned
  # Homebrew Cellar path that vanishes on `brew upgrade zsh`) so the SHELL env
  # var GUI-launched apps inherit tracks the declared login shell. Idempotent —
  # no-ops once cleared. Runs in the primary user's GUI domain via
  # `launchctl asuser`, since activation itself runs as root.
  system.activationScripts.postActivation.text = ''
    # --- clear stale launchctl SHELL override (login-shell migration) ---
    _login_shell="${pkgs.zsh}/bin/zsh"
    _uid="$(id -u ${user} 2>/dev/null || true)"
    if [ -n "$_uid" ]; then
      _cur="$(launchctl asuser "$_uid" launchctl getenv SHELL 2>/dev/null || true)"
      if [ -n "$_cur" ] && [ "$_cur" != "$_login_shell" ] && [ "$_cur" != "/bin/zsh" ]; then
        echo "clearing stale launchctl SHELL override ($_cur)"
        launchctl asuser "$_uid" launchctl unsetenv SHELL || true
      fi
    fi
  '';

  # Raise the open-files limit at login. Direct 1:1 port of the old
  # ~/Library/LaunchAgents/com.user.maxfiles.plist (RunAtLoad LaunchAgent that
  # calls `launchctl limit maxfiles 65536 2097152`). nix-darwin renders the
  # plist and manages load/unload; Label is derived from the attr name.
  launchd.user.agents.maxfiles = {
    serviceConfig = {
      ProgramArguments = [ "/bin/launchctl" "limit" "maxfiles" "65536" "2097152" ];
      RunAtLoad = true;
    };
  };

  # nix-darwin state version. Must track the pinned nix-darwin release's
  # expected value; do not bump casually (semantics-only, like NixOS).
  system.stateVersion = 6;
}
