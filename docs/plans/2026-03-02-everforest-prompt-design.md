# Everforest Dark Hard — Powerlevel10k Prompt Theme Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remap every color in `dot_config/zsh/dot_p10k.zsh` from stock p10k wizard values to the Everforest Dark Hard palette, creating a cohesive terminal aesthetic matching the Neovim colorscheme.

**Architecture:** Single-file edit of `dot_config/zsh/dot_p10k.zsh`. All changes are color value substitutions — no structural changes. The file uses Powerlevel10k's `POWERLEVEL9K_*_FOREGROUND` and `POWERLEVEL9K_*_COLOR` variables, plus inline `%NF` color codes in the `my_git_formatter()` function.

**Tech Stack:** Zsh, Powerlevel10k, Chezmoi

---

## Palette Reference (256-color)

| Role   | Hex       | 256 | Semantic use |
|--------|-----------|-----|--------------|
| fg     | `#d3c6aa` | 187 | Default text |
| green  | `#a7c080` | 144 | Success, clean |
| red    | `#e67e80` | 174 | Error, conflict |
| yellow | `#dbbc7f` | 180 | Modified, warning |
| blue   | `#7fbbb3` | 109 | Directory, info |
| aqua   | `#83c092` | 108 | Tools, active |
| orange | `#e69875` | 173 | Cloud, accent |
| purple | `#d699b6` | 175 | Infra, keywords |
| grey0  | `#7a8478` | 244 | Muted, stale |
| grey1  | `#859289` | 245 | Comments, subtle |
| bg3    | `#414b50` | 239 | Separators |

---

### Task 1: Core prompt — ruler, gap, prompt char, directory

**Files:**
- Modify: `dot_config/zsh/dot_p10k.zsh:168` (ruler)
- Modify: `dot_config/zsh/dot_p10k.zsh:179` (gap)
- Modify: `dot_config/zsh/dot_p10k.zsh:198-200` (prompt char)
- Modify: `dot_config/zsh/dot_p10k.zsh:217-227` (directory)

**Step 1: Edit ruler and gap foreground**

Change line 168: `POWERLEVEL9K_RULER_FOREGROUND=238` → `=239`
Change line 179: `POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_FOREGROUND=238` → `=239`

**Step 2: Edit prompt char colors**

Change line 198: `OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=76` → `=144`
Change line 200: `ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=196` → `=174`

**Step 3: Edit directory colors**

Change line 217: `POWERLEVEL9K_DIR_FOREGROUND=31` → `=109`
Change line 224: `POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=103` → `=245`
Change line 227: `POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=39` → `=109`

**Step 4: Commit**

```bash
git add dot_config/zsh/dot_p10k.zsh
git commit -m "feat(prompt): everforest core — ruler, prompt char, directory"
```

---

### Task 2: Git status — my_git_formatter + VCS segment

**Files:**
- Modify: `dot_config/zsh/dot_p10k.zsh:379-382` (git formatter active colors)
- Modify: `dot_config/zsh/dot_p10k.zsh:495-496` (VCS icon colors)
- Modify: `dot_config/zsh/dot_p10k.zsh:509-511` (VCS fallback colors)

**Step 1: Edit my_git_formatter active colors**

Change line 379: `local      clean='%76F'` → `'%144F'`
Change line 380: `local   modified='%178F'` → `'%180F'`
Change line 381: `local  untracked='%39F'` → `'%109F'`
Change line 382: `local conflicted='%196F'` → `'%174F'`

**Step 2: Edit VCS icon and fallback colors**

Change line 495: `POWERLEVEL9K_VCS_VISUAL_IDENTIFIER_COLOR=76` → `=144`
Change line 509: `POWERLEVEL9K_VCS_CLEAN_FOREGROUND=76` → `=144`
Change line 510: `POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=76` → `=144`
Change line 511: `POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=178` → `=180`

**Step 3: Commit**

```bash
git add dot_config/zsh/dot_p10k.zsh
git commit -m "feat(prompt): everforest git status colors"
```

---

### Task 3: Status, execution time, background jobs, direnv

**Files:**
- Modify: `dot_config/zsh/dot_p10k.zsh:521-546` (status)
- Modify: `dot_config/zsh/dot_p10k.zsh:555` (execution time)
- Modify: `dot_config/zsh/dot_p10k.zsh:567` (background jobs)
- Modify: `dot_config/zsh/dot_p10k.zsh:573` (direnv)

**Step 1: Edit status colors**

Change line 521: `OK_FOREGROUND=70` → `=144`
Change line 527: `OK_PIPE_FOREGROUND=70` → `=144`
Change line 533: `ERROR_FOREGROUND=160` → `=174`
Change line 538: `ERROR_SIGNAL_FOREGROUND=160` → `=174`
Change line 546: `ERROR_PIPE_FOREGROUND=160` → `=174`

**Step 2: Edit execution time, background jobs, direnv**

Change line 555: `COMMAND_EXECUTION_TIME_FOREGROUND=101` → `=180`
Change line 567: `BACKGROUND_JOBS_FOREGROUND=70` → `=108`
Change line 573: `DIRENV_FOREGROUND=178` → `=180`

**Step 3: Commit**

```bash
git add dot_config/zsh/dot_p10k.zsh
git commit -m "feat(prompt): everforest status, timing, jobs, direnv"
```

---

### Task 4: Asdf and language runtime colors

**Files:**
- Modify: `dot_config/zsh/dot_p10k.zsh:580` (asdf default)
- Modify: `dot_config/zsh/dot_p10k.zsh:638-713` (asdf per-tool)

**Step 1: Edit asdf colors**

Change line 580: `ASDF_FOREGROUND=66` → `=108`
Change line 638: `ASDF_RUBY_FOREGROUND=168` → `=174`
Change line 643: `ASDF_PYTHON_FOREGROUND=37` → `=108`
Change line 648: `ASDF_GOLANG_FOREGROUND=37` → `=108`
Change line 653: `ASDF_NODEJS_FOREGROUND=70` → `=144`
Change line 658: `ASDF_RUST_FOREGROUND=37` → `=173`
Change line 663: `ASDF_DOTNET_CORE_FOREGROUND=134` → `=175`
Change line 668: `ASDF_FLUTTER_FOREGROUND=38` → `=109`
Change line 673: `ASDF_LUA_FOREGROUND=32` → `=109`
Change line 678: `ASDF_JAVA_FOREGROUND=32` → `=109`
Change line 683: `ASDF_PERL_FOREGROUND=67` → `=109`
Change line 688: `ASDF_ERLANG_FOREGROUND=125` → `=174`
Change line 693: `ASDF_ELIXIR_FOREGROUND=129` → `=175`
Change line 698: `ASDF_POSTGRES_FOREGROUND=31` → `=109`
Change line 703: `ASDF_PHP_FOREGROUND=99` → `=175`
Change line 708: `ASDF_HASKELL_FOREGROUND=172` → `=173`
Change line 713: `ASDF_JULIA_FOREGROUND=70` → `=144`

**Step 2: Commit**

```bash
git add dot_config/zsh/dot_p10k.zsh
git commit -m "feat(prompt): everforest asdf and language runtime colors"
```

---

### Task 5: Shell indicators and NordVPN

**Files:**
- Modify: `dot_config/zsh/dot_p10k.zsh:719-783` (shell indicators)

**Step 1: Edit shell indicator colors**

Change line 719: `NORDVPN_FOREGROUND=39` → `=109`
Change line 728: `RANGER_FOREGROUND=178` → `=180`
Change line 734: `YAZI_FOREGROUND=178` → `=180`
Change line 740: `NNN_FOREGROUND=72` → `=108`
Change line 746: `LF_FOREGROUND=72` → `=108`
Change line 752: `XPLR_FOREGROUND=72` → `=108`
Change line 758: `VIM_SHELL_FOREGROUND=34` → `=144`
Change line 764: `MIDNIGHT_COMMANDER_FOREGROUND=178` → `=180`
Change line 770: `NIX_SHELL_FOREGROUND=74` → `=109`
Change line 783: `CHEZMOI_SHELL_FOREGROUND=33` → `=108`

**Step 2: Commit**

```bash
git add dot_config/zsh/dot_p10k.zsh
git commit -m "feat(prompt): everforest shell indicator colors"
```

---

### Task 6: System monitors — disk, RAM, swap, load, CPU arch

**Files:**
- Modify: `dot_config/zsh/dot_p10k.zsh:789-820` (system monitors)
- Modify: `dot_config/zsh/dot_p10k.zsh:895` (CPU arch)

**Step 1: Edit system monitor colors**

Change line 789: `DISK_USAGE_NORMAL_FOREGROUND=35` → `=144`
Change line 790: `DISK_USAGE_WARNING_FOREGROUND=220` → `=180`
Change line 791: `DISK_USAGE_CRITICAL_FOREGROUND=160` → `=174`
Change line 802: `RAM_FOREGROUND=66` → `=108`
Change line 808: `SWAP_FOREGROUND=96` → `=175`
Change line 816: `LOAD_NORMAL_FOREGROUND=66` → `=108`
Change line 818: `LOAD_WARNING_FOREGROUND=178` → `=180`
Change line 820: `LOAD_CRITICAL_FOREGROUND=166` → `=173`
Change line 895: `CPU_ARCH_FOREGROUND=172` → `=173`

**Step 2: Commit**

```bash
git add dot_config/zsh/dot_p10k.zsh
git commit -m "feat(prompt): everforest system monitor colors"
```

---

### Task 7: Todo, timewarrior, taskwarrior, per-directory-history, context

**Files:**
- Modify: `dot_config/zsh/dot_p10k.zsh:826-910` (misc segments)

**Step 1: Edit misc segment colors**

Change line 826: `TODO_FOREGROUND=110` → `=109`
Change line 850: `TIMEWARRIOR_FOREGROUND=110` → `=109`
Change line 862: `TASKWARRIOR_FOREGROUND=74` → `=109`
Change line 882: `PER_DIRECTORY_HISTORY_LOCAL_FOREGROUND=135` → `=175`
Change line 883: `PER_DIRECTORY_HISTORY_GLOBAL_FOREGROUND=130` → `=173`
Change line 906: `CONTEXT_ROOT_FOREGROUND=178` → `=173`
Change line 908: `CONTEXT_{REMOTE,REMOTE_SUDO}_FOREGROUND=180` → `=180` (no change)
Change line 910: `CONTEXT_FOREGROUND=180` → `=187`

**Step 2: Commit**

```bash
git add dot_config/zsh/dot_p10k.zsh
git commit -m "feat(prompt): everforest todo, history, context colors"
```

---

### Task 8: Virtualenv, anaconda, pyenv, goenv, node envs, standalone runtime versions

**Files:**
- Modify: `dot_config/zsh/dot_p10k.zsh:930-1221` (runtime environment segments)

**Step 1: Edit Python/Go environment colors**

Change line 930: `VIRTUALENV_FOREGROUND=37` → `=108`
Change line 943: `ANACONDA_FOREGROUND=37` → `=108`
Change line 976: `PYENV_FOREGROUND=37` → `=108`
Change line 1002: `GOENV_FOREGROUND=37` → `=108`

**Step 2: Edit Node environment colors**

Change line 1015: `NODENV_FOREGROUND=70` → `=144`
Change line 1028: `NVM_FOREGROUND=70` → `=144`
Change line 1039: `NODEENV_FOREGROUND=70` → `=144`
Change line 1049: `NODE_VERSION_FOREGROUND=70` → `=144`

**Step 3: Edit standalone runtime version colors**

Change line 1057: `GO_VERSION_FOREGROUND=37` → `=108`
Change line 1065: `RUST_VERSION_FOREGROUND=37` → `=173`
Change line 1073: `DOTNET_VERSION_FOREGROUND=134` → `=175`
Change line 1081: `PHP_VERSION_FOREGROUND=99` → `=175`
Change line 1089: `LARAVEL_VERSION_FOREGROUND=161` → `=174`
Change line 1095: `JAVA_VERSION_FOREGROUND=32` → `=109`
Change line 1105: `PACKAGE_FOREGROUND=117` → `=109`
Change line 1117: `RBENV_FOREGROUND=168` → `=174`
Change line 1130: `RVM_FOREGROUND=168` → `=174`
Change line 1140: `FVM_FOREGROUND=38` → `=109`
Change line 1146: `LUAENV_FOREGROUND=32` → `=109`
Change line 1159: `JENV_FOREGROUND=32` → `=109`
Change line 1172: `PLENV_FOREGROUND=67` → `=109`
Change line 1185: `PERLBREW_FOREGROUND=67` → `=109`
Change line 1195: `PHPENV_FOREGROUND=99` → `=175`
Change line 1208: `SCALAENV_FOREGROUND=160` → `=174`
Change line 1221: `HASKELL_STACK_FOREGROUND=172` → `=173`

**Step 4: Commit**

```bash
git add dot_config/zsh/dot_p10k.zsh
git commit -m "feat(prompt): everforest runtime environment and version colors"
```

---

### Task 9: Infrastructure — kubernetes, terraform, AWS, azure, gcloud

**Files:**
- Modify: `dot_config/zsh/dot_p10k.zsh:1268` (kubernetes)
- Modify: `dot_config/zsh/dot_p10k.zsh:1350-1355` (terraform)
- Modify: `dot_config/zsh/dot_p10k.zsh:1391` (AWS)
- Modify: `dot_config/zsh/dot_p10k.zsh:1402` (AWS EB)
- Modify: remaining azure/gcloud sections

**Step 1: Edit infrastructure colors**

Change line 1268: `KUBECONTEXT_DEFAULT_FOREGROUND=134` → `=175`
Change line 1350: `TERRAFORM_OTHER_FOREGROUND=38` → `=109`
Change line 1355: `TERRAFORM_VERSION_FOREGROUND=38` → `=109`
Change line 1391: `AWS_DEFAULT_FOREGROUND=208` → `=173`
Change line 1402: `AWS_EB_ENV_FOREGROUND=70` → `=144`

Also find and change azure/gcloud foreground values to `=109`.

**Step 2: Commit**

```bash
git add dot_config/zsh/dot_p10k.zsh
git commit -m "feat(prompt): everforest infrastructure colors"
```

---

### Task 10: IP content expansion inline colors

**Files:**
- Modify: `dot_config/zsh/dot_p10k.zsh:1586` (IP content expansion)

**Step 1: Edit IP inline colors**

Change line 1586: `%70F` → `%144F` and `%215F` → `%173F`

**Step 2: Commit**

```bash
git add dot_config/zsh/dot_p10k.zsh
git commit -m "feat(prompt): everforest IP segment inline colors"
```

---

### Task 11: Verify — source the config and visually inspect

**Step 1: Apply via chezmoi and inspect**

```bash
chezmoi diff dot_config/zsh/dot_p10k.zsh
```

Review the diff to ensure only color values changed, no structural modifications.

**Step 2: Verify no syntax errors**

```bash
zsh -c 'source dot_config/zsh/dot_p10k.zsh' 2>&1
```

Should produce no output (no errors).
