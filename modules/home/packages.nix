{
  config,
  pkgs,
  lib,
  caps,
  identity,
  inputs,
  ...
}:

# Core CLI tooling + fonts installed declaratively via nixpkgs (home-manager),
# replacing the CLI/font half of the old dot_config/homebrew/Brewfile.tmpl. The
# macOS-native / GUI / shell-binary remainder stays in Homebrew
# (modules/darwin/homebrew.nix). chezmoi is intentionally NOT included — the
# dotfiles are managed by nix now, not chezmoi.
#
# Font note: home-manager on macOS does not populate ~/Library/Fonts the way
# nix-darwin's fonts.packages populates /Library/Fonts. Per the port contract
# fonts live here; if macOS does not discover them after switch, they should be
# lifted to `fonts.packages` in a darwin module. The bespoke / heavy /
# unconfirmed fonts remain Homebrew casks (see homebrew.nix).

let
  # ─── Fast-moving packages: per-package escape from the stable pin ────────
  # nixpkgs is pinned to 26.05 (flake.nix:8). That line backports fixes but not
  # new upstream releases, so high-cadence tools drift arbitrarily far behind.
  # Everything NOT named here stays on the stable pin — including transitive
  # build inputs, which is exactly why this is explicit selection and not an
  # overlay: an overlay would rewrite pkgs.<name> globally, rebuilding dependent
  # stable packages and losing binary-cache hits. gh/yazi/neovim/delta/bat/fd/
  # btop already match stable and are deliberately unlisted — the lag is a
  # cadence mismatch in specific tools, not the channel.
  # To add a tool: append here AND move it to fastMovingPackages below. The
  # assertion at the bottom fails the build if you forget the second half.
  fastMovingPackages = [
    "mise" # runtime manager; its config stays a raw symlinked dotfile
    "uv" # also drives the mcpSync activation hook in sync-hooks.nix
    "fzf"
    "lazygit"
    "zoxide"
    "ripgrep" # binary is `rg`
    # atuin ships ~2x/week and its `init zsh` output is version-dependent, so a
    # stale binary silently disables features the config asks for. Stable 26.05
    # serves 18.15.2 (2026-04-16); the tmux popup that config.{sync,local}.toml
    # enables via `[tmux] enabled = true` needs >= 18.12.0, and a machine left on
    # an older binary emits no ATUIN_TMUX_POPUP export at all — the config reads
    # as ignored rather than as unsupported (diagnosed 2026-08-07 on a host
    # running a pre-18.12 installer copy). Config without the matching binary is
    # not a working contract, so nix owns both or neither.
    "atuin"
  ];

  # ─── Broken-on-stable packages: same unstable input, different reason ────
  # These are NOT cadence problems. Each one is a package the stable pin cannot
  # build, taken from unstable only until the stable channel can. Kept separate
  # so `fastMovingPackages` keeps meaning what its comment says it means and a
  # reader can tell a policy choice from a workaround. Both lists feed the same
  # `pkgsFresh`, so the mechanism is identical.
  # 26.05 (f6107e54, 2026-08-28) ships statix-0-unstable-2026-05-14 whose
  # checkPhase fails on Darwin: cargo insta snapshot collapsible_let_in against
  # the channel rustc. Unstable has 0.5.8-unstable-2026-07-17, hydra-cached.
  # Drop when 26.05 builds pkgs.statix unmodified (NixOS/nixpkgs#524695 is on
  # master; not backported as of this pin).
  stableBrokenPackages = [
    "statix" # Nix linter used by LazyVim's Nix extra and flake checks
  ];

  # Every name drawn from the unstable input, for whichever reason.
  unstableNames = fastMovingPackages ++ stableBrokenPackages;

  # A second nixpkgs that deliberately does not follow the stable input.
  # `legacyPackages` rather than `import`: it is the same attribute set here
  # (this repo sets no `nixpkgs.config` anywhere — no allowUnfree, no overlay
  # stack — so the defaults already match), and flake.nix's statix check reaches
  # the input the same way. One instantiation path, not two.
  pkgsFresh = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};

  freshPackages = map (name: pkgsFresh.${name}) unstableNames;

  # Each capability gate gets its own binding rather than being inlined into one
  # `++` chain, so a consumer can inspect the fully assembled stable set instead
  # of just the base list. `with pkgs;` is repeated per binding because the
  # original single `with` covered the whole concatenation expression, which no
  # longer exists as a single expression.
  stablePackages = with pkgs; [
    # ─── CLI utilities (all machines) ───────────────────────────────────
    bat # syntax-highlighting cat
    brotli
    curl
    fd # fast find
    grex # regex generator
    htop
    jq
    gnumake # provides `make`
    tree
    wget
    xz
    eza # modern ls
    fastfetch
    yazi # TUI file manager
    p7zip # 7zz archive preview for yazi
    resvg # SVG preview for yazi
    yq-go # mikefarah yq (matches the brew `yq`, not the python yq)
    btop
    ffmpeg
    neovim
    cloc
    mosh # resilient remote shell for headless tmux
    cloudflared # cloudflare tunnel client
    glow # markdown renderer
    nmap
    poppler-utils # pdftotext/pdfimages/… — nixpkgs `poppler` is the library only
    television # fuzzy finder TUI; binary is `tv`
    typst # typesetting system
    yt-dlp

    # ─── Git & version control ──────────────────────────────────────────
    git
    git-extras
    git-filter-repo
    git-secrets
    delta # git-delta
    gh
    jujutsu # `jj`; .config/jj/config.toml is already linked by dotfiles.nix
    lazydocker

    # ─── Development shell tooling ───────────────────────────────────────
    gnused # gnu-sed
    shellcheck
    tmux # binary only; tmux config stays a raw symlinked dotfile
    nixd # Nix LSP, including flake-provided nix-darwin/HM option sets
    nixfmt # formatter used by LazyVim's Nix extra and nixd
    cmake
    ninja
    lychee # link checker
    markdownlint-cli2
    semgrep

    # ─── Repo workflow tooling ──────────────────────────────────────────
    # These are not optional conveniences: the documented workflows break
    # without them. `just` drives every recipe in the Justfile AND the
    # side-channel step in bootstrap.sh; `lefthook` runs the git hooks defined
    # in lefthook.yml and is invoked by CLAUDE.md, `just lefthook`,
    # scripts/sync-side-channels.sh (which runs `lefthook install`), and
    # dotfiles-hygiene-ci.yml; `gitleaks` backs the staged-secret job in
    # lefthook.yml. All of them were undeclared hand-brews until now.
    # (lefthook replaced pre-commit on 2026-08-29; the language-agnostic file
    # checks now run through `uvx --from pre-commit-hooks==6.0.0`, so uv above
    # is load-bearing for the hooks too.)
    just
    lefthook
    gitleaks
    actionlint # lints .github/workflows/
    yamllint

    # ─── Security tooling (SAST / DAST / supply chain) ───────────────────
    # Consumed by the security agents in the agents-k3-sec registry
    # (security-auditor, sast-scanner, dependency-auditor, secrets-auditor,
    # staging-pentester, terraform-security-reviewer). Vulnerability data is
    # fetched at runtime (trivy DB, OSV, nuclei-templates auto-update), so
    # these do not drift stale on the stable pin the way fast-moving CLIs do.
    # semgrep/gitleaks/nmap live above and are not repeated here. OWASP ZAP
    # is deliberately excluded: the dast-staging-guidelines skill runs the
    # official zap-baseline Docker image (OrbStack) instead of the nix Java
    # app.
    trivy # deps + IaC + container images
    osv-scanner # cross-ecosystem lockfile audit
    trufflehog # verified secrets in git history
    checkov # Terraform policy baseline
    hadolint # Dockerfile lint
    nuclei # template-driven DAST
    ffuf # web content discovery
    testssl # TLS config; binary is `testssl.sh`
    gosec # Go SAST
    cargo-audit # RustSec advisories against Cargo.lock
    cargo-deny # Rust dep/licence bans
    bandit # Python SAST
    pip-audit # Python dep audit

    # ─── Language / secrets / runtime managers ──────────────────────────
    # NOTE: `uv` and `mise` are declared in fastMovingPackages above, not here.
    # python314: pinned interpreter for the vendored tools (requires-python
    # >= 3.14). Hard requirement with NO fallback: sync-hooks.nix references
    # the same store path, so if a future pin ever drops the attr, both sites
    # must move together — eval fails loudly here first.
    python314
    age # age encryption CLI, for manual use (no age secrets are declared here)
  ];

  # ─── GUI base fonts (mirror the Brewfile gui gate) ──────────────────────
  guiFonts = lib.optionals caps.gui (
    with pkgs;
    [
      jetbrains-mono
      nerd-fonts.meslo-lg # font-meslo-lg-nerd-font
      nerd-fonts.symbols-only # font-symbols-only-nerd-font
      nerd-fonts.jetbrains-mono # font-jetbrains-mono-nerd-font
    ]
  );
  # ─── Dev-flavored fonts, high-confidence nixpkgs attrs (dev gate) ───────
  # The uncertain / heavy remainder stays as dev-gated Homebrew casks.
  devFonts = lib.optionals caps.dev (
    with pkgs;
    [
      fira-code
      inconsolata
      liberation_ttf # font-liberation
      dejavu_fonts
      victor-mono
      nerd-fonts.dejavu-sans-mono # font-dejavu-sans-mono-nerd-font
    ]
  );

  # ─── Work-only policy tooling ──────────────────────────────────────────
  workTools = lib.optionals (identity == "work") (
    with pkgs;
    [
      conftest
    ]
  );

  # Concatenation order is identical to the original `++` chain — `home.packages`
  # is a list, so reordering would change the derivation even though the set of
  # packages is unchanged.
  allStable = stablePackages ++ guiFonts ++ devFonts ++ workTools;

  # Names claimed by BOTH channels. Inspects the fully assembled stable set, not
  # just the base list, so a future fast-mover added to a capability-gated block
  # cannot slip past the guard. (It only sees the blocks active for the host
  # being evaluated, but `nix flake check --all-systems` covers every host, so a
  # collision hidden behind another machine's caps still fails CI.)
  # `pname or ""` because a few font derivations do not set pname.
  duplicated = builtins.filter (
    name: builtins.any (p: (p.pname or "") == name) allStable
  ) unstableNames;
in
{
  # Without this, declaring a package in both channels surfaces as a
  # home-manager file collision at activation ("collision between ... /bin/rg")
  # — loud, but pointing at the symptom rather than the cause.
  assertions = [
    {
      assertion = duplicated == [ ];
      message =
        "modules/home/packages.nix: "
        + lib.concatStringsSep ", " duplicated
        + " declared in BOTH the unstable lists (fastMovingPackages / "
        + "stableBrokenPackages) and the stable package list. "
        + "Each package must come from exactly one channel — delete the stable "
        + "entry.";
    }
  ];

  home.packages = allStable ++ freshPackages;
}
