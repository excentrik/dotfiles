# Dotfiles repository structure

This document describes how the repo is organized and how to extend it. For installation and usage, see [README.md](README.md).

## Directory layout

| Path | Purpose |
|------|--------|
| **meta/** | Dotbot configs: `base.yaml` (always run) and per-host/role YAMLs |
| **meta/hosts/** | Host profiles: list of role names for that environment (wsl, unix, osx, docker) |
| **meta/roles/** | One YAML per “package” (bash, vim, git, docker, tmux, editor, python, brew, etc.) |
| **extensions/<id>/** | Optional self-contained extension roots with host profiles, roles, and helpers |
| **home_files/** | Source of truth for files linked into `~` (e.g. `.bashrc`, `.aliases/*.sh`, `.vimrc`) |
| **helpers/** | Setup scripts run by Dotbot when roles are installed |
| **system/** | OS-specific scripts (Homebrew list, OS X defaults) |
| **dotbot**, **dotbot-brew**, **dotbot-apt/**, **dotbot-role-deps/** | Dotbot, the Homebrew plugin submodule, and local apt/role-dependency directive plugins |
| **AGENTS.md** | Shared AI-assistant repository instructions |

**Note:** `install.conf.yaml` at the repo root is **not** used by `./install`. The installer uses only `meta/base.yaml` and `meta/roles/*.yaml`. It is legacy/OSX-oriented and can be removed or kept for reference.

Native Windows is out of scope for this repository. Windows users should run the existing `wsl` host profile inside WSL, which `./install` auto-detects from `/proc/version`.

Azure Linux/CBL-Mariner VMs and other non-WSL Linux hosts should use the existing `unix` profile. Add a new host profile only when the host needs a different role set, not just because it uses a different Linux distribution.

## Adding a new host

1. Create `meta/hosts/<hostname>.yaml`.
2. Add one line per role: `rolename: ~` (e.g. `bash: ~`, `vim: ~`).
3. Ensure the host is detectable in `install` (e.g. add a case for `$OSTYPE` or environment) or pass the host explicitly: `./install <hostname>`.

## Adding a new role

1. Create `meta/roles/<name>.yaml` with Dotbot directives:
   - **link:** — map `~/.something` to paths under `home_files/`.
   - **shell:** — run a script under `helpers/` or one-off commands.
   - (Optional) **depends** — role names that must run before this role.
   - (Optional) **tap** / **brew** / **cask** — Homebrew packages for macOS hosts.
   - (Optional) **apt** — Linux package dependencies for apt/dpkg or yum/rpm hosts; the directive name is historical.
2. Add any new dotfile content under `home_files/` (or `home_files/.aliases/` for alias scripts).
3. If the role needs setup logic, add a script in `helpers/` and invoke it from the role YAML via `shell:`.
4. Add the role name to the appropriate host file(s) in `meta/hosts/`, or add it to another role's `depends` directive if it should be installed automatically before that role.

Do not add a Dotbot copy plugin without a concrete need. Repo-managed files should be linked from `home_files/`, while generated or machine-local files should be created by idempotent helpers.

## Extensions

An extension lives in `extensions/<id>/` and has an `extension.conf` containing
`id=<id>` plus an optional comma-separated `hosts=<host>[,<host>...]` entry.
The directory ID and manifest ID must match. Extension IDs, host IDs, and role
names use `[a-z0-9][a-z0-9_-]*`.

Primary extension hosts are defined by `meta/hosts/<host>.yaml` and require
matching `meta/host-families/<host>` metadata whose value is one of the core
family identifiers `osx`, `unix`, `wsl`, or `docker`. Core host addons live at
`meta/host-addons/<core-host>.yaml`; constrained `DOTFILES_*` defaults live at
`meta/host-env/<host>.env` and never replace caller-provided values. For a core
host, extension defaults are applied in extension-ID order, so the first
extension providing an unset variable wins.
`meta/role-addons/<role>.yaml` runs after its base role. Addons are ordered by
extension ID and cannot declare dependencies. Addon YAML is parsed with the
vendored safe YAML loader; any mapping key named `depends` is rejected, while
comments and ordinary string values containing that word are allowed. Core and
extension role roots share dependency expansion, and duplicate role names are
rejected.

Host profiles and host addons use only constrained list entries such as
`- role: ~`; comments and blank lines are allowed, while blank values,
malformed names, and other YAML shapes are rejected. Passive `home_files/`
symlinks must resolve to contained targets; dangling symlinks fail closed.

The optional `detect-host` must be executable and may claim at most one
declared host. Silence or a successful no-claim falls back to core detection;
nonzero exit, stderr, malformed output, multiple claims, or an undeclared
claim fails. Host-family metadata is always explicit for primary extension
hosts.

Active content includes `extension.conf`, `meta/`, `helpers/`, `detect-host`,
`validate.sh`, and Copilot hooks. It must be a contained regular file and match
`HEAD` in normal mode. `DOTFILES_EXTENSIONS_MODE=development` permits staged
active files only when the worktree is clean for those paths. `home_files/` is
passive content: it must be contained but need not be tracked.

Extensions are ordinary directories inside the main repository. Nested
repositories and submodules are unsupported for active extension content
because active-code integrity is checked against the main repository's `HEAD`.

An optional executable `validate.sh` is run only by `helpers/validate.sh`, in
extension-ID order. Silent exit zero passes; nonzero exit or any stderr fails.
It is not run during ordinary installation.

When the `copilot` role is selected, the optional
`helpers/copilot-prerequisite` hook runs in extension-ID order with
`DOTFILES_EXTENSION_ID` and `DOTFILES_EXTENSION_ROOT` set. Silent output or
`permit` allows the role, `skip` omits it, and `fail`, nonzero exit, stderr, or
malformed output fails closed.

Extension detectors and Copilot prerequisite hooks execute during installer
dry-runs because they determine selected behavior. Dotbot actions and submodule
updates remain dry-run and non-mutating. These active files are
integrity-checked and should be side-effect-free. Extension validators run only
through validation, not ordinary installation.

Set `DOTFILES_EXTENSIONS=0` to disable discovery. Zero-argument `./install`
then requires an explicit core host. `DOTFILES_PROMPT_HOST` accepts a
hostname-like ASCII token up to 253 characters with valid 1–63 character
labels; invalid values use Bash's normal hostname expansion. Without an
`extensions/` directory, the baseline installation behavior is unchanged.

The optional `claude` role depends on the public `bun` role, so Bun-based Claude
extensions and tooling can run without a separate setup. Bun is also selectable
directly through its own role.

## Scripts

### Root

- **install** — Main entry: detects or uses host, updates submodules to recorded commits unless Dotbot dry-run is requested, runs Dotbot with `meta/base.yaml` then each role from `meta/hosts/<host>.yaml` after expanding role-local `depends` directives. Optional extra roles: `./install wsl some_role`; Dotbot flags such as `--dry-run`, `--only`, and `--except` are passed through. Set `DOTFILES_UPDATE_SUBMODULES=1` to intentionally update submodules from upstream remotes. Use a temporary `HOME` when testing dry-runs from a worktree.
- **install-role** — Run one or more roles only (e.g. `./install-role vim git`), expanding role-local `depends` directives first. Does not run base or full host. Dotbot flags can appear before or after role names.
- **generate_shortcuts_documentation.sh** — Regenerates the “Commands available” section in README.md from the alias/function comments in `home_files/.aliases/`. Use `./generate_shortcuts_documentation.sh --check` to detect README command-doc drift without modifying the file.
- `DOTFILES_NO_INTERACTIVE=1` skips helpers that would prompt for input, including Homebrew maintenance and macOS system-defaults setup.
- `--bootstrap` or `DOTFILES_BOOTSTRAP=1` lets Linux/WSL installs install missing role-local `apt` packages through the host package manager.

To update submodules without running install scripts, use `git submodule update --init --recursive` for recorded commits or add `--remote` to intentionally advance submodules from upstream branches.

## Shell integrations

Bash and zsh enable direnv with the shell-specific `direnv hook` when the `direnv` command is available. The `direnv` role installs that command for host profiles that include it, while the guarded hook keeps shells working on hosts where direnv is absent.

zsh and Oh My Zsh enable [atuin](https://atuin.sh) shell history with `atuin init zsh --disable-up-arrow` when the `atuin` command is available; the guarded hook is placed last so atuin owns the Ctrl-R binding while the Up-arrow keeps native zsh history behaviour. The `atuin` role (currently in the `osx` host) installs atuin via Homebrew and links the managed `home_files/atuin/config.toml` to `~/.config/atuin/config.toml`. atuin is intentionally **not** wired into bash: its bash integration records history through `bash-preexec`/`ble.sh`, which this repo does not install.

## Alias files

`home_files/.bash_aliases` sources every readable `~/.aliases/*.sh` file at shell startup, but only files linked by `meta/base.yaml` or a selected role are installed into `~/.aliases/`.

| Source file | Installed by | Notes |
|-------------|--------------|-------|
| `home_files/.aliases/functions.sh` | `meta/base.yaml` | Common shell functions; always linked before host roles |
| `home_files/.aliases/common.sh` | `meta/base.yaml` | Common aliases; always linked before host roles |
| `home_files/.aliases/other.sh` | `meta/base.yaml` | Miscellaneous aliases; always linked before host roles |
| `home_files/.aliases/claude.sh` | `meta/roles/claude.yaml` | Installed by hosts that include the Claude role |
| `home_files/.aliases/copilot.sh` | `meta/roles/copilot.yaml` | Installed by hosts that include the Copilot role |
| `home_files/.aliases/docker_aliases.sh` | `meta/roles/docker.yaml` | Docker host aliases |
| `home_files/.aliases/docker_container_aliases.sh` | `meta/roles/docker_container.yaml` | Container-oriented aliases |
| `home_files/.aliases/ssh_tunnels.sh` | `meta/roles/docker_container.yaml` | Container SSH tunnel helpers |
| `home_files/.aliases/osx.sh` | `meta/roles/osx.yaml` | macOS-specific aliases |
| `home_files/.aliases/python_aliases.sh` | `meta/roles/python.yaml` | Python aliases |

### helpers/

`helpers/extensions.sh` and `helpers/hosts.sh` are co-required modules and
must both be sourced before `extensions_initialize`. The host module uses the
extension module's foundational arrays and primitives; extension
initialization calls the host module's functions.

| Script | Purpose |
|--------|---------|
| aliases_cleanup.sh | Removes broken symlinks under `~/.aliases` left by renamed/deleted alias files |
| editor_setup.sh | Chooses vi/nano if EDITOR unset, writes to `~/.extra`; optional `/usr/local/bin/edit` for non-SSH |
| bun_setup.sh | Installs Bun for the `bun` role: Homebrew on macOS, official user-local installer on Linux/WSL without modifying shell rc files |
| git_setup.sh | Copies `~/.gitconfig` to `~/.gitconfig_local` if needed; adds GIT_SSH and (on OSX) credential helper |
| python_setup.sh | Python environment setup (role: python) |
| brew_setup.sh | Homebrew initialization (role: brew, OSX) |
| xcode_cli_setup.sh | Xcode Command Line Tools setup only; does not install full Xcode (role: xcode_cli, OSX). Headless/CI macOS hosts must preinstall CLT (e.g. via MDM or `xcode-select --install` in a setup step) before running `./install`; the helper deliberately skips its interactive GUI prompt when stdin is not a TTY or `DOTFILES_NO_INTERACTIVE` is set. |
| copilot_setup.sh | Ensures Node.js 24+ (installs user-local Node 24 when needed) and installs/updates GitHub Copilot CLI with npm |
| hosts.sh | Generic host family, profile, detection, environment, and role collection helpers; source after `extensions.sh` |
| ohmyzsh_setup.sh | Copies `~/.oh-my-zsh` from the checked-out Oh My Zsh submodule when safe (role: ohmyzsh) |
| node_setup.sh | Node environment setup (if used by a role) |
| osx_setup.sh | OS X–specific setup (if used by a role) |
| validate.sh | Non-mutating validation checks for scripts, extensions, role links, and Dotbot dry-runs; `--extensions` selects extension-only checks |
| role_dependencies.sh | Shared role dependency expansion and graph validation used by `install`, `install-role`, and validation |

### system/

| Script | Purpose |
|--------|---------|
| brew.sh | Installs Homebrew packages (referenced from legacy `install.conf.yaml`, not from current meta/roles) |
| osxdefaults.sh | OS X system defaults (same legacy reference) |

## Roles not enabled by any host

The `hush` role is intentionally not listed in any `meta/hosts/*.yaml`. It
creates `~/.hushlogin` to silence the system login banner and, in concert with
`HUSH=1` (exported from `~/.extra`), suppresses the per-shell alias/source
banners emitted by `~/.bashrc`, `~/.zshrc`, and the shared aliases. Opt in
per-machine via `./install <host> hush` rather than adding it to a host
profile, so the choice is explicit per environment.

## Git configuration

The `git` role force-links the managed `home_files/git/gitconfig` to `~/.gitconfig` with Dotbot backups enabled. Before that link is created, `helpers/git_setup.sh` preserves an existing user-owned `~/.gitconfig` as `~/.gitconfig_local` when the local include does not already exist.

`home_files/git/gitconfig` should contain shared defaults only. Machine-local identity, credential helpers, and other personal overrides belong in `~/.gitconfig_local`, which is included by the managed config and is not tracked by this repository. Repeat installs do not copy the managed `~/.gitconfig` symlink back into `~/.gitconfig_local`, which avoids duplicating the committed config in the local include.

Before installing the `git` role on an existing machine, diff the current `~/.gitconfig` against `home_files/git/gitconfig` and move only machine-local additions into `~/.gitconfig_local`. Do not duplicate shared sections, includes, aliases, or filters in both files; keep each setting owned by either the managed config or the local include to avoid Git config failures and confusing overrides.

This conditional `~/.gitconfig` preservation is intentionally implemented in `helpers/git_setup.sh`, not through a generic copy plugin, because it depends on the existing target state and must avoid copying the managed symlink on repeat installs.

## Claude configuration

The `claude` role copies shared Claude Code defaults from `home_files/.claude/settings.json` into `~/.claude/settings.json` only when the local file is missing or still points at the old repo-managed symlink. After installation the file is local and can be edited per host.

Do not commit Claude credentials, project/session history, generated skills, plugin caches, telemetry, paste cache, local settings, or other generated state from `~/.claude` or `~/.claude.json`.

## Copilot configuration

The `copilot` role copies shared GitHub Copilot CLI defaults from `home_files/.copilot/settings.json` into `~/.copilot/settings.json` only when the local file is missing or still points at the old repo-managed symlink. After installation the file is local and can be edited per host.

The `copilot` role also copies `home_files/.copilot/copilot-instructions.md` into `~/.copilot/copilot-instructions.md` only when the local file is missing or still points at the old repo-managed symlink. Existing local instruction files are preserved.

The `copilot` role links the five repository-managed skills from `home_files/.copilot/skills/` into `~/.copilot/skills/`: `evidence-research`, `grill-with-docs`, `handoff`, `tdd`, and `teach`. Copilot discovers per-skill directory symlinks, so pulling dotfiles updates the managed skills immediately while unrelated personal skills remain separate. The helper migrates exact copies from the previous installation behavior and refuses ambiguous same-name directories or symlinks.

`helpers/copilot_setup.sh` ensures a Node.js 24 runtime for Copilot. If the current `node` is older than 24 (or missing), it installs the latest `v24.x` Node build to `~/.local/node-v24`, symlinks `node`/`npm`/`npx`/`corepack` into `~/.local/bin`, and then installs/updates `@github/copilot`.

The `copilot` role enables experimental mode by default with `"experimental": true` in `~/.copilot/settings.json`. `helpers/copilot_setup.sh` adds that setting to existing local settings only when the key is missing, so an explicit local `"experimental": false` is preserved. The `copilot` role also links `home_files/bin/copilot` into `~/bin/copilot`, which is earlier on PATH than `~/.local/bin`; that wrapper preserves `--no-experimental` for one command and maps `DOTFILES_COPILOT_EXPERIMENTAL=0` to `--no-experimental`.

Only portable preferences, footer settings, and reviewed repository-managed skills belong in the default Copilot configuration. Do not commit Copilot auth config, OAuth state, MCP config, command history, logs, session state, unreviewed generated skills, plugin caches, installed plugin metadata, experiment assignment caches, local permissions, trusted folders, login/user state, or stores from `~/.copilot`.

## Role dependencies

Use a role-local `depends` directive to list role names that must run before the current role:

```yaml
- depends:
    - runtime
```

Both `./install` and `./install-role` expand dependencies recursively, de-duplicate roles, and preserve dependency-first ordering before invoking Dotbot. The `dotbot-role-deps` plugin then treats `depends` as a no-op during the Dotbot pass because expansion has already happened.

## Host-specific package directives

Declare role package dependencies directly in `meta/roles/<role>.yaml` next to the links and setup scripts that need them.

Use Homebrew directives for macOS packages:

```yaml
- tap:
    - oven-sh/bun

- brew:
    - oven-sh/bun/bun
```

Use the local `apt` directive for Linux-family package dependencies:

```yaml
- apt:
    - curl
    - unzip
```

`./install` and `./install-role` add host-specific directive exclusions before invoking Dotbot: macOS skips `apt`, while Linux/WSL/docker skip Homebrew directives. On Linux-family hosts, the `apt` directive uses apt/dpkg when available and falls back to yum/rpm for RPM-based hosts such as Azure Linux/CBL-Mariner. Normal Linux-family installs report missing packages without installing anything. `--dry-run` prints the package-manager commands instead of running them.

Keep default package roles conservative. Tools such as `git-lfs`, `pipx`, `uv`,
and developer utilities like `rg`, `fd`, `fzf`, `bat`, `ncdu`, and `yq` remain
manual or opt-in unless a dedicated role is added later. Bun remains optional
and selectable directly through its own role, and the `claude` role also pulls
it in automatically. Tools such as `kubectl`, Docker, Java, Kerberos tooling,
and Volta are not managed by dotfiles package roles.

## Link safety and forced targets

Dotbot link defaults are defined in `meta/base.yaml`: links are created as needed, relinked, not forced, and backed up. Roles can override these defaults for targets that must be owned by a selected shell/profile.

| Role | Target | Behavior | Reason |
|------|--------|----------|--------|
| `git` | `~/.gitconfig` | `force: true`, `backup: true` | The repo manages the shared Git config while machine-local settings live in `~/.gitconfig_local`. |
| `zsh` | `~/.zshrc` | `force: true`, `backup: true` | The plain zsh role must replace any existing zsh startup file with the repo-managed one. |
| `atuin` | `~/.config/atuin/config.toml` | `force: true`, `backup: true` | The repo manages the shared atuin config; an existing local config is backed up so it adopts the managed default. atuin's encryption key and history stay in `~/.local/share/atuin/` and are never managed. |

The `ohmyzsh` role intentionally uses the safe link defaults for `~/.zshrc` instead of forcing or cleaning it. Its helper copies the checked-out `oh-my-zsh` submodule into `~/.oh-my-zsh` so future dotfiles submodule updates do not automatically change the local shell framework; move conflicting local files aside manually before installing the role.

Do not add `force: true` to a role casually. Prefer the base defaults unless a target must be replaced for the role to work, and document why the forced target is safe.
