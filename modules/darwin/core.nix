{ config, pkgs, lib, user, ... }:

# Darwin system core: nix daemon ownership, unfree policy, primary user,
# login-shell pin, and the maxfiles launchd agent. Everything per-machine
# flows in through specialArgs (user); no hostname checks live here.
{
  # Determinate Nix owns and manages the nix daemon on these machines, so the
  # nix-darwin module must NOT try to manage nix itself (installing profiles,
  # rewriting nix.conf, restarting the daemon).
  nix.enable = false;

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
  # NOTE (divergence from the retired script, which pinned /bin/zsh): per the
  # port contract this uses the nix-store pkgs.zsh. The current system
  # generation's zsh path is GC-root-protected, so it is stable; if a reviewer
  # prefers the always-present /bin/zsh for login resilience, swap this to
  # `shell = "/bin/zsh";` (a plain path string is also accepted here).
  #
  # NOTE (reviewer): setting `shell` for a macOS-created (i.e. not
  # nix-darwin-managed / knownUsers) account relies on newer nix-darwin driving
  # `dscl … UserShell` during activation. If the pinned nix-darwin release
  # refuses to touch an unmanaged user's shell, add `users.knownUsers` + a
  # `uid` for this user, or fall back to a chsh activation snippet.
  users.users.${user} = {
    name = user;
    home = "/Users/${user}";
    shell = pkgs.zsh;
  };

  # Register the login shell in /etc/shells so it is a valid choice.
  environment.shells = [ pkgs.zsh ];

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
