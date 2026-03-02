# Everforest Dark Hard — Powerlevel10k Prompt Theme

## Goal

Remap every color in `dot_config/zsh/dot_p10k.zsh` from stock p10k wizard values to the Everforest Dark Hard palette, creating a cohesive terminal aesthetic that matches the Neovim colorscheme.

## Palette Reference (256-color)

| Role   | Hex       | 256 |
|--------|-----------|-----|
| fg     | `#d3c6aa` | 187 |
| green  | `#a7c080` | 144 |
| red    | `#e67e80` | 174 |
| yellow | `#dbbc7f` | 180 |
| blue   | `#7fbbb3` | 109 |
| aqua   | `#83c092` | 108 |
| orange | `#e69875` | 173 |
| purple | `#d699b6` | 175 |
| grey0  | `#7a8478` | 244 |
| grey1  | `#859289` | 245 |
| grey2  | `#9da9a0` | 247 |
| bg3    | `#414b50` | 239 |

## Semantic Mapping Rules

- **Success/clean** → green (144)
- **Error/conflict** → red (174)
- **Modified/warning** → yellow (180)
- **Directory/info** → blue (109)
- **Tools/active** → aqua (108)
- **Cloud/accent** → orange (173)
- **Infra/keywords** → purple (175)
- **Muted/stale** → grey0 (244), grey1 (245)
- **Separators** → bg3 (239)
- **Default text** → fg (187)

## Changes

Single file: `dot_config/zsh/dot_p10k.zsh`

All changes are color value substitutions — no structural changes.

### Core prompt
- Ruler/gap foreground: 238 → 239
- Prompt char OK: 76 → 144
- Prompt char Error: 196 → 174
- Dir: 31 → 109, shortened: 103 → 245, anchor: 39 → 109

### Git (my_git_formatter + VCS segment)
- clean: `%76F` → `%144F`
- modified: `%178F` → `%180F`
- untracked: `%39F` → `%109F`
- conflicted: `%196F` → `%174F`
- VCS icon: 76 → 144, clean/untracked: 76 → 144, modified: 178 → 180

### Status
- OK/OK pipe: 70 → 144
- Error/signal/pipe: 160 → 174

### Right-side segments
- Execution time: 101 → 180
- Background jobs: 70 → 108
- Direnv: 178 → 180
- Asdf default: 66 → 108

### Language runtimes
- Ruby: 168 → 174, Python/Go: 37 → 108, Node: 70 → 144
- Rust: 37 → 173, .NET: 134 → 175, PHP: 99 → 175
- Java/Lua: 32 → 109, Perl: 67 → 109, Flutter: 38 → 109
- Erlang: 125 → 174, Elixir: 129 → 175, Postgres: 31 → 109
- Haskell: 172 → 173, Julia: 70 → 144, Laravel: 161 → 174

### Infrastructure
- Kubernetes: 134 → 175, Terraform: 38 → 109
- AWS: 208 → 173, AWS EB: 70 → 144, Azure/GCloud: 109

### Shell indicators
- Ranger/Yazi/MC: 178 → 180, Nnn/Lf/Xplr: 72 → 108
- Vim shell: 34 → 144, Nix: 74 → 109, Chezmoi: 33 → 108
- NordVPN: 39 → 109, Todo/Timewarrior: 110 → 109, Taskwarrior: 74 → 109

### System monitors
- Disk: normal 35 → 144, warning 220 → 180, critical 160 → 174
- RAM: 66 → 108, Swap: 96 → 175
- Load: normal 66 → 108, warning 178 → 180, critical 166 → 173
- CPU arch: 172 → 173

### Misc
- Context root: 178 → 173, remote: 180 → 180, default: 180 → 187
- Package: 117 → 109
- Per-dir-history: local 135 → 175, global 130 → 173
- IP RX: `%70F` → `%144F`, TX: `%215F` → `%173F`

### Virtualenv/Anaconda/Pyenv/Goenv
- All python/go env segments: 37 → 108

### Node environments
- Nodenv/Nvm/Nodeenv/Node version: 70 → 144

### Other runtimes
- Go version: 37 → 108, Rust version: 37 → 173, .NET version: 134 → 175
- PHP version: 99 → 175, Java version: 32 → 109
- Rbenv/Rvm: 168 → 174, Fvm: 38 → 109
- Luaenv: 32 → 109, Jenv: 32 → 109
- Plenv/Perlbrew: 67 → 109, Phpenv: 99 → 175
- Scalaenv: 160 → 174, Haskell Stack: 172 → 173
