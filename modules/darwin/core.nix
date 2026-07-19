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

  # Login-shell pin. The primary account is a pre-existing macOS admin user,
  # not a nix-darwin-owned user: the pinned nix-darwin release only applies
  # users.users.* properties to users.knownUsers, and explicitly warns not to
  # add the admin user there. postActivation below therefore owns the actual
  # Directory Services update instead of pretending users.users.* is enough.
  #
  # The pin is the LITERAL /bin/zsh, not pkgs.zsh: the retired script existed
  # because a non-OS shell path (Homebrew cellar, and equally a nix store
  # path) can dangle across upgrades/GC and brick login — /bin/zsh is the one
  # shell Apple guarantees. Interactive shell richness comes from z4h config,
  # not the login-shell binary.
  #
  # Home metadata remains necessary because nix-darwin's Home Manager bridge
  # reads it for system.primaryUser. This does not opt the admin account into
  # users.knownUsers or claim nix-darwin manages its Directory Services fields.
  users.users.${user}.home = "/Users/${user}";

  # /bin/zsh is already in /etc/shells; keep pkgs.zsh registered too so a
  # store zsh remains a valid `chsh` choice without being the login pin.
  environment.shells = [ pkgs.zsh "/bin/zsh" ];

  # Apply the login shell and clear any stale `launchctl setenv SHELL <path>`
  # override (e.g. a versioned Homebrew Cellar path that vanishes on upgrade).
  # Both operations are idempotent. Activation runs as root; launchctl work is
  # explicitly routed into the primary user's GUI domain.
  system.activationScripts.postActivation.text = ''
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
