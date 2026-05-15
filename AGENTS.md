# Repository instructions for AI assistants

## Commands

- `./install` - auto-detect the host and run `meta/base.yaml` plus all roles listed for that host.
- `./install <host> [<extra-roles...>]` - install a specific host profile (`osx`, `unix`, `wsl`, or `docker`) and optionally append extra roles.
- `./install --dry-run` and `./install <host> --dry-run` - pass Dotbot dry-run through without mutating the home directory or updating submodules.
- `./install-role <roles...> [dotbot-options...]` - run only the named role configs with Dotbot `--verbose`; Dotbot options may appear before or after role names.
- `DOTFILES_UPDATE_SUBMODULES=1 ./install` - intentionally update submodules from upstream remotes before installing; default installs use recorded commits.
- `DOTFILES_NO_INTERACTIVE=1 ./install` - run the installer without interactive prompts where helpers support it.
- `helpers/validate.sh` - run non-mutating Linux/WSL-oriented validation.
- `helpers/validate.sh --all-roles` - include non-Linux roles such as macOS, zsh, and Mongo.
- `source ~/.bash_profile` - reload the installed Bash configuration.
- `./generate_shortcuts_documentation.sh` - regenerate the README "Commands available" section; run it only from a shell that has already sourced these dotfiles because it calls `list_dotfiles_functions`.

Install commands are mutating unless `--dry-run` is used. They create symlinks under `~` and may back up or overwrite real files. Before installing a role, check affected targets such as `ls -la ~/.bashrc` to avoid losing local customizations.

## Architecture

This is a Dotbot-based dotfiles repository with a host/role model. `dotbot` and `dotbot-brew` are git submodules. The root `./install` script detects the host from `$OSTYPE` plus Docker/WSL checks, updates submodules to recorded commits by default, runs `meta/base.yaml`, then reads `meta/hosts/<host>.yaml` and applies each listed `meta/roles/<role>.yaml`. Extra role names passed after the host are applied after the host roles.

`meta/base.yaml` links core shell files and common alias scripts, then roles layer on package-specific links and setup scripts. Role YAMLs usually link files from `home_files/` into `~` and may invoke setup scripts from `helpers/`; the `brew` role additionally uses Dotbot Brew directives.

Host profiles are intentionally small role lists. `unix` and `wsl` install Bash, prompt, editor, inputrc, Vim, tmux, Python, Git, and Claude aliases/setup. `docker` omits Git and Claude setup but includes Docker/container aliases. `osx` adds Homebrew, Mongo, zsh, OS X defaults, and submodule setup.

Shell startup flows through `home_files/.bash_profile` to `home_files/.bashrc`. `.bashrc` sources `~/.path`, `~/.exports`, and `~/.profile`, then calls `load_aliases()` from `~/.bash_aliases`, which sources every readable `~/.aliases/*.sh`. It then sources `~/.bash_prompt`, `~/.startup`, and `~/.extra` when present.

There are two zsh variants. The `zsh` role links a plain `home_files/.zshrc`; the `ohmyzsh` role runs `helpers/ohmyzsh_setup.sh` and links `home_files/.ohmyzshrc`. Do not add both to the same host profile.

## Conventions

- Add a new role by creating `meta/roles/<name>.yaml`, placing linked dotfiles under `home_files/`, adding helper logic in `helpers/` when needed, and listing the role in the relevant `meta/hosts/<host>.yaml`.
- Put shared shell functions and aliases in `home_files/.aliases/*.sh`; base and role configs link those files into `~/.aliases/`, where they are auto-sourced in shell glob order.
- Add a short comment immediately before aliases/functions that should appear in README command docs; `list_dotfiles_functions` discovers descriptions by grepping those comments from linked alias files.
- Keep personal or machine-local settings out of the repo. `~/.extra` is sourced by Bash for local shell customizations, and `~/.gitconfig_local` is included by `home_files/git/gitconfig`.
- `helpers/git_setup.sh` may create `~/.gitconfig_local` from an existing `~/.gitconfig` and appends `GIT_SSH` setup to `~/.extra`; preserve that local-customization behavior.
- `install.conf.yaml`, `system/brew.sh`, and `system/osxdefaults.sh` are legacy references and are not used by the current `./install` flow.
- The `hush` role creates `~/.hushlogin`; setting `HUSH=1` also suppresses shell startup alias/source messages.
- Only files linked from `meta/base.yaml` or `meta/roles/*.yaml` are installed. Some files under `home_files/.aliases/` are currently dormant unless a role links them.

## Role and helper details

- Dotbot defaults usually use `backup: true` and `force: false`, but some roles intentionally force targets: `git` forces `~/.gitconfig`, `zsh` forces `~/.zshrc`, and `ohmyzsh` cleans then forces `~/.zshrc`.
- `helpers/editor_setup.sh`, `helpers/git_setup.sh`, `helpers/python_setup.sh`, and `helpers/node_setup.sh` append idempotent blocks to `~/.extra`; preserve their grep-before-append pattern when adding local setup.
- `helpers/brew_setup.sh` is interactive and can run `brew update`, `brew upgrade`, and `brew cleanup`; `helpers/osx_setup.sh` asks for sudo and changes macOS defaults. Do not run these as validation.
- `helpers/claude_setup.sh` installs `@anthropic-ai/claude-code` globally with npm when `claude` is missing.
- `helpers/ohmyzsh_setup.sh` downloads and executes the upstream Oh My Zsh installer with `wget`; it exits if `zsh` is unavailable.
- `home_files/.path` prepends system paths, `~/bin`, `~/.local/bin`, and `.`; Bash and zsh later de-duplicate `PATH` while keeping the first occurrence.
- The Bash prompt in `home_files/.bash_prompt` computes Git branch details on prompt render. The zsh prompt in `home_files/.zsh_prompt` updates Git worktree state on `chpwd`/`precmd` and can skip Git checks when `skip_zsh_git` is set.
- `meta/roles/mongo.yaml` currently references `home_files/.aliases/mongo.sh`, but that file is absent; account for this before running or modifying the Mongo role.
