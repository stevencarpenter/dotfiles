# Package mapping: nix to Homebrew and mise (DFM-50)

Scope: the 84 packages in `modules/home/packages.nix` (67 stable, 7 unstable-pinned, 10 fonts) plus the
work-only `conftest`. Brew versions come from `brew info --json=v2 <name>` run on 2026-10-11.
`Brewfile` section 2 holds the mapped entries.

Result: 81 mapped to brew (71 formulae, 10 font casks), 3 dropped (`nixd`, `nixfmt`, `statix`),
0 mapped to mise. `conftest` (work-only) maps to brew `conftest` 0.71.1 and is commented out in the Brewfile.

Decisions:

- mise already provides go, java, scala, sbt, terraform, gradle, goreleaser, npm and go tool packages, LSP servers,
  tree-sitter, duckdb and the Firstmate toolchain (`home/.config/mise/`). No nix package duplicates any of them,
  so no mise file changed.
- `python314` maps to brew `python@3.14`. mise `python = "3.14"` is the alternative; it was not added.
- `mise` itself comes from brew. `scripts/sync-side-channels.sh` already runs `mise install` and `mise upgrade`.
- Unstable pin: `flake.nix` on branch `daily-nix-bump` pins nixpkgs-unstable at
  `7dd199b0e2993e37b4775ed66b1c291699608c9f` (2026-10-07). Branch `main` pins `c9fe7d12cd78d1adcd12dd15e24432dde5b155a0`
  (2026-09-30). Pinned versions below were read from `pkgs/by-name/*/package.nix` at the `7dd199b0` rev.
- Fonts: none of the 10 font casks duplicates a section 1 font cask. Section 1 already holds
  `font-meslo-for-powerlevel10k`, `font-sketchybar-app-font`, `font-input`, `font-intel-one-mono`, `font-iosevka`
  and `font-inconsolata-go-nerd-font`.
- Capability gating (`caps.gui`, `caps.dev`) is not carried over. Section 2 installs all fonts.
- GNU names: brew installs `gmake` and `gsed` unprefixed only under the `gnubin` path. Check PATH use before relying on `make` or `sed`.

| Nix attribute | Brew formula or cask, or drop | Brew version | Notes |
| --- | --- | --- | --- |
| `mise` | brew `mise` | 2026.10.7 | unstable pin 2026.9.18 at nixpkgs 7dd199b0; brew 2026.10.7. Brew is newer |
| `uv` | brew `uv` | 0.13.0 | unstable pin 0.12.22 at nixpkgs 7dd199b0; brew 0.13.0. Brew is newer |
| `fzf` | brew `fzf` | 0.74.4 | unstable pin 0.74.4 at nixpkgs 7dd199b0; brew 0.74.4. Brew is equal |
| `lazygit` | brew `lazygit` | 0.66.0 | unstable pin 0.66.0 at nixpkgs 7dd199b0; brew 0.66.0. Brew is equal |
| `zoxide` | brew `zoxide` | 0.10.0 | unstable pin 0.10.0 at nixpkgs 7dd199b0; brew 0.10.0. Brew is equal |
| `ripgrep` | brew `ripgrep` | 15.2.0 | unstable pin 15.2.0 at nixpkgs 7dd199b0; brew 15.2.0. Brew is equal |
| `statix` | drop |  | nix linter; useless once flake checks go. Brew has statix 0.5.8 but nothing outside nix uses it |
| `bat` | brew `bat` | 0.26.1 |  |
| `brotli` | brew `brotli` | 1.2.0 |  |
| `curl` | brew `curl` | 8.22.0 | keg-only in brew (system curl stays first on PATH) |
| `fd` | brew `fd` | 10.5.0 |  |
| `grex` | brew `grex` | 1.4.6 |  |
| `htop` | brew `htop` | 3.5.3 |  |
| `jq` | brew `jq` | 1.8.2 |  |
| `gnumake` | brew `make` | 4.4.1 | installs as `gmake`; `make` needs the gnubin path, otherwise Xcode make is used |
| `tree` | brew `tree` | 2.3.2 |  |
| `wget` | brew `wget` | 1.25.0 |  |
| `xz` | brew `xz` | 5.8.4 |  |
| `eza` | brew `eza` | 0.23.5 |  |
| `fastfetch` | brew `fastfetch` | 2.69.0 |  |
| `yazi` | brew `yazi` | 26.9.1 |  |
| `p7zip` | brew `sevenzip` | 26.04 | yazi preview wants `7zz`; brew `p7zip` 17.06 ships `7z`/`7za` only |
| `resvg` | brew `resvg` | 0.48.1 |  |
| `yq-go` | brew `yq` | 4.54.1 | brew `yq` is mikefarah (Go) yq 4.x, same as yq-go |
| `btop` | brew `btop` | 1.4.7 |  |
| `ffmpeg` | brew `ffmpeg` | 9.0.2 |  |
| `neovim` | brew `neovim` | 0.12.6 |  |
| `cloc` | brew `cloc` | 2.10 |  |
| `mosh` | brew `mosh` | 1.4.0 |  |
| `cloudflared` | brew `cloudflared` | 2026.10.0 |  |
| `glow` | brew `glow` | 3.0.0 |  |
| `nmap` | brew `nmap` | 7.991 |  |
| `poppler-utils` | brew `poppler` | 26.10.0 | brew poppler includes pdftotext/pdfimages |
| `television` | brew `television` | 0.15.9 |  |
| `typst` | brew `typst` | 0.15.1 |  |
| `yt-dlp` | brew `yt-dlp` | 2026.8.19 |  |
| `git` | brew `git` | 2.56.0 |  |
| `git-extras` | brew `git-extras` | 7.5.0 |  |
| `git-filter-repo` | brew `git-filter-repo` | 2.47.0 |  |
| `git-secrets` | brew `git-secrets` | 1.3.0 |  |
| `delta` | brew `git-delta` | 0.20.1 |  |
| `gh` | brew `gh` | 2.102.0 |  |
| `jujutsu` | brew `jj` | 0.46.0 | binary `jj` |
| `lazydocker` | brew `lazydocker` | 0.25.2 |  |
| `gnused` | brew `gnu-sed` | 4.10 | installs as `gsed`; `sed` needs the gnubin path |
| `shellcheck` | brew `shellcheck` | 0.11.0 |  |
| `tmux` | brew `tmux` | 3.8 |  |
| `nixd` | drop |  | Nix LSP; no brew formula (brew info fails); drop after nix removal |
| `nixfmt` | drop |  | Nix formatter; brew has nixfmt 1.5.0 but it only serves nix files; drop after nix removal |
| `cmake` | brew `cmake` | 4.4.4 |  |
| `ninja` | brew `ninja` | 1.13.2 |  |
| `lychee` | brew `lychee` | 0.24.2 |  |
| `markdownlint-cli2` | brew `markdownlint-cli2` | 0.23.3 |  |
| `semgrep` | brew `semgrep` | 1.180.0 |  |
| `just` | brew `just` | 1.58.0 |  |
| `lefthook` | brew `lefthook` | 2.2.1 |  |
| `gitleaks` | brew `gitleaks` | 8.30.1 |  |
| `actionlint` | brew `actionlint` | 1.7.12 |  |
| `yamllint` | brew `yamllint` | 1.38.0 |  |
| `trivy` | brew `trivy` | 0.75.0 |  |
| `osv-scanner` | brew `osv-scanner` | 2.6.0 |  |
| `trufflehog` | brew `trufflehog` | 3.99.2 |  |
| `checkov` | brew `checkov` | 3.3.20 |  |
| `hadolint` | brew `hadolint` | 2.15.1 |  |
| `nuclei` | brew `nuclei` | 3.11.1 |  |
| `ffuf` | brew `ffuf` | 2.3.0 |  |
| `testssl` | brew `testssl` | 3.2.4 | nix exposes `testssl.sh`; brew binary name not verified |
| `gosec` | brew `gosec` | 2.29.0 |  |
| `cargo-audit` | brew `cargo-audit` | 0.22.2 |  |
| `cargo-deny` | brew `cargo-deny` | 0.20.2 |  |
| `bandit` | brew `bandit` | 1.9.4 |  |
| `pip-audit` | brew `pip-audit` | 2.10.1 |  |
| `python314` | brew `python@3.14` | 3.14.8 | brew chosen over mise: many brew formulae (semgrep, checkov, bandit) already depend on python@3.14, so it is installed anyway. mise `python = "3.14"` is the alternative; not added |
| `age` | brew `age` | 1.3.2 |  |
| `jetbrains-mono` | cask `font-jetbrains-mono` | 2.304 |  |
| `nerd-fonts.meslo-lg` | cask `font-meslo-lg-nerd-font` | 3.5.1 |  |
| `nerd-fonts.symbols-only` | cask `font-symbols-only-nerd-font` | 3.5.1 |  |
| `nerd-fonts.jetbrains-mono` | cask `font-jetbrains-mono-nerd-font` | 3.5.1 |  |
| `fira-code` | cask `font-fira-code` | 6.2 |  |
| `inconsolata` | cask `font-inconsolata` | latest | cask version is `latest`; distinct from section 1 `font-inconsolata-go-nerd-font` |
| `liberation_ttf` | cask `font-liberation` | 2.1.5,7261482 |  |
| `dejavu_fonts` | cask `font-dejavu` | 2.37 |  |
| `victor-mono` | cask `font-victor-mono` | 1.5.6 |  |
| `nerd-fonts.dejavu-sans-mono` | cask `font-dejavu-sans-mono-nerd-font` | 3.5.1 |  |
| `conftest` | brew `conftest` (work-only, commented out) | 0.71.1 | Present only when `identity == "work"`. Not counted in the 84. |
