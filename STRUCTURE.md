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

**Note:** `install.conf.yaml` at the repo root is **not** used by `./install`. The installer uses only `meta/base.yaml` and `meta/roles/*.yaml`. It is legacy/OSX-oriented and can be removed or kept for reference.

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

## Scripts

### Root

- **install** — Main entry: detects or uses host, updates submodules, runs Dotbot with `meta/base.yaml` then each role from `meta/hosts/<host>.yaml`. Optional extra roles: `./install wsl some_role`.
- **install-role** — Run one or more roles only (e.g. `./install-role vim git`). Does not run base or full host.
- **generate_shortcuts_documentation.sh** — Regenerates the “Commands available” section in README.md by running `list_dotfiles_functions`. **Must be run in a shell that has already sourced the dotfiles** (e.g. `source ~/.bash_profile`), since it relies on aliases/functions from `~/.aliases/`.

### helpers/

| Script | Purpose |
|--------|---------|
| editor_setup.sh | Chooses vi/nano if EDITOR unset, writes to `~/.extra`; optional `/usr/local/bin/edit` for non-SSH |
| git_setup.sh | Copies `~/.gitconfig` to `~/.gitconfig_local` if needed; adds GIT_SSH and (on OSX) credential helper |
| python_setup.sh | Python environment setup (role: python) |
| brew_setup.sh | Homebrew initialization (role: brew, OSX) |
| ohmyzsh_setup.sh | Oh My Zsh setup (role: ohmyzsh) |
| vim_plugin_install.sh | Installs Vim plugins (role: vim_plugins) |
| node_setup.sh | Node environment setup (if used by a role) |
| osx_setup.sh | OS X–specific setup (if used by a role) |

### system/

| Script | Purpose |
|--------|---------|
| brew.sh | Installs Homebrew packages (referenced from legacy `install.conf.yaml`, not from current meta/roles) |
| osxdefaults.sh | OS X system defaults (same legacy reference) |
