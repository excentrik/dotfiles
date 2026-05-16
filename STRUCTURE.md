# Dotfiles repository structure

This document describes how the repo is organized and how to extend it. For installation and usage, see [README.md](README.md).

## Directory layout

| Path | Purpose |
|------|--------|
| **meta/** | Dotbot configs: `base.yaml` (always run) and per-host/role YAMLs |
| **meta/hosts/** | Host profiles: list of role names for that environment (wsl, unix, osx, docker) |
| **meta/roles/** | One YAML per “package” (bash, vim, git, docker, tmux, editor, python, brew, etc.) |
| **home_files/** | Source of truth for files linked into `~` (e.g. `.bashrc`, `.aliases/*.sh`, `.vimrc`) |
| **helpers/** | Setup scripts run by Dotbot when roles are installed |
| **system/** | OS-specific scripts (Homebrew list, OS X defaults) |
| **dotbot**, **dotbot-brew** | Git submodules: Dotbot and its Homebrew plugin |
| **AGENTS.md** | Shared AI-assistant repository instructions |

**Note:** `install.conf.yaml` at the repo root is **not** used by `./install`. The installer uses only `meta/base.yaml` and `meta/roles/*.yaml`. It is legacy/OSX-oriented and can be removed or kept for reference.

Native Windows is out of scope for this repository. Windows users should run the existing `wsl` host profile inside WSL, which `./install` auto-detects from `/proc/version`.

## Adding a new host

1. Create `meta/hosts/<hostname>.yaml`.
2. Add one line per role: `rolename: ~` (e.g. `bash: ~`, `vim: ~`).
3. Ensure the host is detectable in `install` (e.g. add a case for `$OSTYPE` or environment) or pass the host explicitly: `./install <hostname>`.

## Adding a new role

1. Create `meta/roles/<name>.yaml` with Dotbot directives:
   - **link:** — map `~/.something` to paths under `home_files/`.
   - **shell:** — run a script under `helpers/` or one-off commands.
   - (Optional) **brew** / **cask** / **tap** — only with the dotbot-brew plugin (see `meta/roles/brew.yaml`).
2. Add any new dotfile content under `home_files/` (or `home_files/.aliases/` for alias scripts).
3. If the role needs setup logic, add a script in `helpers/` and invoke it from the role YAML via `shell:`.
4. Add the role name to the appropriate host file(s) in `meta/hosts/`.

Do not add a Dotbot copy plugin without a concrete need. Repo-managed files should be linked from `home_files/`, while generated or machine-local files should be created by idempotent helpers.

## Scripts

### Root

- **install** — Main entry: detects or uses host, updates submodules to recorded commits unless Dotbot dry-run is requested, runs Dotbot with `meta/base.yaml` then each role from `meta/hosts/<host>.yaml`. Optional extra roles: `./install wsl some_role`; Dotbot flags such as `--dry-run`, `--only`, and `--except` are passed through. Set `DOTFILES_UPDATE_SUBMODULES=1` to intentionally update submodules from upstream remotes. Use a temporary `HOME` when testing dry-runs from a worktree.
- **install-role** — Run one or more roles only (e.g. `./install-role vim git`). Does not run base or full host. Dotbot flags can appear before or after role names.
- **generate_shortcuts_documentation.sh** — Regenerates the “Commands available” section in README.md from the alias/function comments in `home_files/.aliases/`. Use `./generate_shortcuts_documentation.sh --check` to detect README command-doc drift without modifying the file.
- `DOTFILES_NO_INTERACTIVE=1` skips helpers that would prompt for input, including Homebrew maintenance and macOS system-defaults setup.
- `--bootstrap` or `DOTFILES_BOOTSTRAP=1` lets Linux/WSL installs with `apt` install missing role package dependencies before each role runs. Without bootstrap, package dependencies are only reported.

To update submodules without running install scripts, use `git submodule update --init --recursive` for recorded commits or add `--remote` to intentionally advance submodules from upstream branches.

## Alias files

`home_files/.bash_aliases` sources every readable `~/.aliases/*.sh` file at shell startup, but only files linked by `meta/base.yaml` or a selected role are installed into `~/.aliases/`.

| Source file | Installed by | Notes |
|-------------|--------------|-------|
| `home_files/.aliases/functions.sh` | `meta/base.yaml` | Common shell functions; always linked before host roles |
| `home_files/.aliases/common.sh` | `meta/base.yaml` | Common aliases; always linked before host roles |
| `home_files/.aliases/other.sh` | `meta/base.yaml` | Miscellaneous aliases; always linked before host roles |
| `home_files/.aliases/claude.sh` | `meta/roles/claude.yaml` | Installed by hosts that include the Claude role |
| `home_files/.aliases/docker_aliases.sh` | `meta/roles/docker.yaml` | Docker host aliases |
| `home_files/.aliases/docker_container_aliases.sh` | `meta/roles/docker_container.yaml` | Container-oriented aliases |
| `home_files/.aliases/ssh_tunnels.sh` | `meta/roles/docker_container.yaml` | Container SSH tunnel helpers |
| `home_files/.aliases/osx.sh` | `meta/roles/osx.yaml` | macOS-specific aliases |
| `home_files/.aliases/python_aliases.sh` | `meta/roles/python.yaml` | Python aliases |

### helpers/

| Script | Purpose |
|--------|---------|
| editor_setup.sh | Chooses vi/nano if EDITOR unset, writes to `~/.extra`; optional `/usr/local/bin/edit` for non-SSH |
| git_setup.sh | Copies `~/.gitconfig` to `~/.gitconfig_local` if needed; adds GIT_SSH and (on OSX) credential helper |
| python_setup.sh | Python environment setup (role: python) |
| brew_setup.sh | Homebrew initialization (role: brew, OSX) |
| xcode_cli_setup.sh | Xcode Command Line Tools setup only; does not install full Xcode (role: xcode_cli, OSX) |
| ohmyzsh_setup.sh | Copies `~/.oh-my-zsh` from the checked-out Oh My Zsh submodule when safe (role: ohmyzsh) |
| vim_plugin_install.sh | Installs Vim plugins (role: vim_plugins) |
| node_setup.sh | Node environment setup (if used by a role) |
| osx_setup.sh | OS X–specific setup (if used by a role) |
| validate.sh | Non-mutating validation checks for scripts, role links, and Dotbot dry-runs |
| package_bootstrap.py | Reports or explicitly installs Linux/WSL apt package dependencies declared per role |

### system/

| Script | Purpose |
|--------|---------|
| brew.sh | Installs Homebrew packages (referenced from legacy `install.conf.yaml`, not from current meta/roles) |
| osxdefaults.sh | OS X system defaults (same legacy reference) |

## Git configuration

The `git` role force-links the managed `home_files/git/gitconfig` to `~/.gitconfig` with Dotbot backups enabled. Before that link is created, `helpers/git_setup.sh` preserves an existing user-owned `~/.gitconfig` as `~/.gitconfig_local` when the local include does not already exist.

`home_files/git/gitconfig` should contain shared defaults only. Machine-local identity, credential helpers, and other personal overrides belong in `~/.gitconfig_local`, which is included by the managed config and is not tracked by this repository. Repeat installs do not copy the managed `~/.gitconfig` symlink back into `~/.gitconfig_local`, which avoids duplicating the committed config in the local include.

This conditional `~/.gitconfig` preservation is intentionally implemented in `helpers/git_setup.sh`, not through a generic copy plugin, because it depends on the existing target state and must avoid copying the managed symlink on repeat installs.

## Package bootstrap metadata

Linux/WSL package bootstrap metadata lives in `meta/packages/<role>.json`, where `<role>` must match a role config in `meta/roles/`. Metadata is intentionally JSON so `helpers/package_bootstrap.py` can parse it with Python's standard library and avoid adding a YAML parser dependency before packages are installed.

Each metadata file may declare command dependencies:

```json
{
  "description": "Vim role dependencies",
  "commands": [
    {
      "name": "vim",
      "apt": ["vim"]
    }
  ]
}
```

Normal installs report missing commands and apt package hints without installing anything. `--bootstrap` or `DOTFILES_BOOTSTRAP=1` is required for installation, and `--dry-run` prints the apt commands instead of running them. macOS/Homebrew bootstrap is intentionally deferred; keep Homebrew package migration separate from Linux/WSL apt metadata.

## Link safety and forced targets

Dotbot link defaults are defined in `meta/base.yaml`: links are created as needed, relinked, not forced, and backed up. Roles can override these defaults for targets that must be owned by a selected shell/profile.

| Role | Target | Behavior | Reason |
|------|--------|----------|--------|
| `git` | `~/.gitconfig` | `force: true`, `backup: true` | The repo manages the shared Git config while machine-local settings live in `~/.gitconfig_local`. |
| `zsh` | `~/.zshrc` | `force: true`, `backup: true` | The plain zsh role must replace any existing zsh startup file with the repo-managed one. |

The `ohmyzsh` role intentionally uses the safe link defaults for `~/.zshrc` instead of forcing or cleaning it. Its helper copies the checked-out `oh-my-zsh` submodule into `~/.oh-my-zsh` so future dotfiles submodule updates do not automatically change the local shell framework; move conflicting local files aside manually before installing the role.

Do not add `force: true` to a role casually. Prefer the base defaults unless a target must be replaced for the role to work, and document why the forced target is safe.
