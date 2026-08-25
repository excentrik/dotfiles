# Dotfiles

Dotfile management using [Dotbot](https://github.com/anishathalye/dotbot). For directory layout, adding hosts/roles, and script reference, see [STRUCTURE.md](STRUCTURE.md). (Note: `install.conf.yaml` in the repo root is legacy and not used by `./install`.)

Brief introduction to dotfiles:
* [Getting started with dotfiles](https://medium.com/@webprolific/getting-started-with-dotfiles-43c3602fd789)
* [Managing your dotfiles](http://www.anishathalye.com/2014/08/03/managing-your-dotfiles/)

## Dependencies

* git
* python

Optional dependencies depending on the environment.

## Installation

```bash
~$ git clone --recursive git@github.com:excentrik/dotfiles.git ~/.dotfiles
```

For default installation (automatically detects host):

```bash
~/.dotfiles$ ./install
~/.dotfiles$ ./install --dry-run
```

For installing a specific host:

```bash
~/.dotfiles$ ./install <host> [<roles...>]
~/.dotfiles$ ./install <host> --dry-run
# see meta/hosts/ for available hosts
# see meta/roles/ for available roles
```

Native Windows is not a supported host. On Windows, install these dotfiles inside WSL using the `wsl` host profile, which `./install` auto-detects when run from WSL.

For installing a single role/package:

```bash
~/.dotfiles$ ./install-role <roles...>
~/.dotfiles$ ./install-role <roles...> --dry-run
# see meta/roles/ for available roles
```

If you don't want dotfiles to ask for any user input, you can use the `DOTFILES_NO_INTERACTIVE` flag, such as:
```bash
~/.dotfiles$ DOTFILES_NO_INTERACTIVE=1 ./install
```
On macOS, this skips the interactive Homebrew maintenance helper and the macOS system-defaults helper so unattended installs do not prompt for sudo or apply system settings.

On Linux/WSL hosts, installs report missing packages from role-local `apt` sections without installing them. The directive supports apt/dpkg and yum/rpm hosts. To explicitly allow missing packages to be installed as roles run, use bootstrap mode:

```bash
~/.dotfiles$ ./install --bootstrap
~/.dotfiles$ DOTFILES_BOOTSTRAP=1 ./install
~/.dotfiles$ ./install-role claude --bootstrap
```

When combined with `--dry-run`, bootstrap prints the package-manager commands it would run without installing packages. macOS uses role-local Homebrew directives (`tap`, `brew`, and `cask`) instead.

## Extensions

Optional extensions live under `extensions/<id>/`. Each extension has an
`extension.conf` containing `id=<id>` and, when it provides primary host
profiles, an optional comma-separated `hosts=<host>[,<host>...]` entry. The
directory name and manifest ID must match. Host and role identifiers, including
extension IDs, must match `[a-z0-9][a-z0-9_-]*`.

An extension may provide `meta/hosts/<host>.yaml` profiles and matching
`meta/host-families/<host>` metadata. Every primary extension host needs an
explicit family from the core vocabulary `osx`, `unix`, `wsl`, or `docker`;
core hosts use the equivalent files under `meta/`. Host profiles and core-host
addons use constrained entries such as `- role: ~`; comments and blank lines
are allowed, but other YAML shapes are rejected. A host detector at
`detect-host` is optional. A detector that exits successfully and
prints nothing yields to core detection. A nonzero exit, stderr, malformed
output, multiple claims, or an undeclared host claim is an error. A detector
must make at most one declared host claim.

Active extension content consists of `extension.conf`, metadata, helpers,
detectors, validators, and Copilot hooks. It must be regular, contained within
the extension root, and match `HEAD` in normal mode. Set
`DOTFILES_EXTENSIONS_MODE=development` to accept staged active code, provided
the worktree is clean for those paths and the files are present in the index.
`home_files/` is passive content: it must remain contained, but may be
untracked. Dangling symlinks are rejected because their containment cannot be
proven. Set `DOTFILES_EXTENSIONS=0` to disable discovery; then
zero-argument `./install` requires an explicit core host, and extension hosts
are unavailable.

Extensions are ordinary directories inside the main repository. Nested
repositories and submodules are unsupported for active extension content
because the active-code integrity check must match the main repository's
`HEAD`.

Selected extension hosts can supply core host addons under
`meta/host-addons/<core-host>.yaml`. Host environment defaults use constrained
`DOTFILES_*` assignments and never override values supplied by the caller. For
a core host, active extensions apply defaults in extension-ID order; when
extensions provide the same unset variable, the first extension's value wins.
Role addons run after their base role in extension-ID order and cannot declare
dependencies. Addon YAML is parsed with the vendored safe YAML loader, and any
mapping key named `depends` is rejected; comments and ordinary string values
containing that word are allowed.

Core and extension roles share dependency expansion across roots. Duplicate
role names are rejected.

An optional extension-root `validate.sh` is active code. It must be a contained,
executable regular file that satisfies the active-code integrity rule.
`helpers/validate.sh` runs validators in extension-ID order; silent exit zero
passes, while nonzero exit or any stderr is a visible validation failure.
Ordinary installs do not run extension validators.

When the `copilot` role is selected, extensions may provide the executable
`extensions/<id>/helpers/copilot-prerequisite` hook. Hooks run in extension-ID
order with `DOTFILES_EXTENSION_ID` and `DOTFILES_EXTENSION_ROOT` set. Silent
output or `permit` allows Copilot, `skip` omits the core role, and `fail`,
nonzero exit, stderr, or malformed output fails closed.

Extension detectors and Copilot prerequisite hooks execute during installer
dry-runs because they determine host and role selection. Dotbot actions and
submodule updates remain dry-run and non-mutating. These active files are
integrity-checked and should be side-effect-free. Extension validators run only
through `helpers/validate.sh`, not during ordinary installation.

`DOTFILES_PROMPT_HOST` accepts an ASCII hostname-like value up to 253
characters, with 1-63 character labels that start and end alphanumeric.
Invalid values fall back to Bash's built-in hostname expansion.

With no `extensions/` directory, the baseline host and role behavior is
unchanged. Test extension-enabled checkouts with isolated temporary `HOME`
directories and `--dry-run --exit-on-failure`; never use a real home for
validation.

The optional `claude` role depends on the public `bun` role, so Bun-based Claude
extensions and tooling can run without a separate setup. Bun is also selectable
directly through its own role.

The macOS host installs and selects **Xcode Command Line Tools only** via the `xcode_cli` role. It does not install full Xcode.

The `tmux` role expects tmux >= 3.2 for the full configuration. tmux >= 3.3 is recommended for passthrough support used by OSC 52/OSC 8 and iTerm2 image protocol workflows; older versions skip guarded features.

You can run these installation commands safely multiple times, if you think that helps with better installation.

`./install` updates submodules to the commits recorded by this repository by default. To intentionally update submodules from their upstream remotes before installing, set `DOTFILES_UPDATE_SUBMODULES=1`.

To update submodules without running any install steps, use Git directly:

```bash
~/.dotfiles$ git submodule update --init --recursive
```

That checks out the submodule commits recorded by this repository. To intentionally move submodules to the latest commits from their configured upstream branches without installing:

```bash
~/.dotfiles$ git submodule update --init --recursive --remote
```

After using `--remote`, review `git status` and commit any submodule gitlink changes you want to keep.

## Validation

Run non-mutating validation checks before changing install scripts or role metadata:

```bash
~/.dotfiles$ helpers/validate.sh
```

By default, validation checks Linux/WSL-oriented hosts (`unix`, `wsl`, and `docker`). Azure Linux/CBL-Mariner VMs use the existing `unix` profile. To include every role, including macOS and zsh roles:

```bash
~/.dotfiles$ helpers/validate.sh --all-roles
```

Use `helpers/validate.sh --extensions` for extension-only checks.

Validation also checks that the generated "Commands available" section is up to date. If that check fails, regenerate it with `./generate_shortcuts_documentation.sh` instead of editing the generated section manually.

When testing install dry-runs from a worktree, use a temporary `HOME` so existing symlinks from another checkout do not affect the result:

```bash
~/.dotfiles$ HOME="$(mktemp -d)" ./install unix --dry-run
```

Use the same `unix` dry-run for non-WSL Linux VMs before installing remotely.

## Remote install preflight

Before installing onto an existing machine, inspect local-only state without printing secret-bearing file contents. Use metadata-only checks for paths that Dotbot may replace or that must stay local:

```bash
~/.dotfiles$ ssh <host> 'for path in ~/.extra ~/.gitconfig_local ~/.gitconfig ~/.bashrc ~/.bash_profile ~/.profile ~/.config/systemd/user ~/.kube ~/.claude/settings.json ~/.claude/skills ~/.claude/projects ~/.copilot/settings.json ~/.copilot/skills ~/.copilot/sessions ~/.copilot/logs /etc/profile.d; do if [ -e "$path" ]; then stat -c "%n | %F | %s bytes | %y" "$path"; else printf "%s | missing\n" "$path"; fi; done'
```

Preserve machine-specific shell snippets in `~/.extra` and machine-specific Git settings in `~/.gitconfig_local`. Keep kubeconfig contents, user/system services, Claude/Copilot sessions, unreviewed generated skills, caches, logs, plugin runtime state, auth/OAuth/API state, credentials, private keys, and system-managed `/etc` state out of this repository. The Copilot role links the reviewed skills into `~/.copilot/skills/` during installation so personal skills can coexist beside them and update with the dotfiles checkout.

## Loading source files

In order to load the dotfiles, you need to run:
```bash
~$ source ~/.bash_profile
```

## Customization

All linked files should be left as they are, unless you plan to commit changes to the dotfiles repo.

Before installing on a machine that already has local shell startup customizations, move machine-specific snippets you still need into `~/.extra` so Dotbot can safely link the repo-managed startup files. Keep host-specific SSH agent/keychain setup, credentials, private paths, and other local state out of the repo.

To add a custom  behaviour to your shell, such as personal aliases, etc:
```bash
~/$ touch .extra
# Edit .extra with whatever customization you want.
# Example (for default OSX prompt):
# export PS1="\h:\w \u\$ ";
~/$ source .extra # To load .extra for current shell
```

## License

See `LICENSE.md` for details.

## Commands available

Run `list_dotfiles_functions` to get a list of available commands:

```bash
b                                                                 # Run one command for multiple final arguments in parallel. Usage: b kubectl logs -f -- pod-1 pod-2
clcd                                                              # cd into a directory and launch claude
cleanup_ds                                                        # Recursively delete `.DS_Store` files under the current path
confirm                                                           # Confirmation wrapper. Usage: confirm rm -rf /tmp/folder
cpcd                                                              # cd into a directory and launch copilot
dot_progress                                                      # Fancy progress function from Landley's Aboriginal Linux. Usage: rm -rfv /foo | dot_progress
escape                                                            # Uber useful when you need to translate a weird path into single-argument string.
extract                                                           # Extra many types of compressed packages
fs                                                                # Determine size of a file or total size of a directory
getHostIp                                                         # Get the IP of the host inside a Docker container
is_running_inside_container                                       # Detect if this command is running inside a docker container
kill_processes                                                    # Kill processes matching a pattern after confirmation. Usage: kill_processes ssh
la                                                                # List all files colorized in long format, including dot files
list_dotfiles_functions                                           # List all function available in a shell
ll                                                                # Alias to use GNU ls and print directories first, with alphanumeric sorting
man                                                               # Enable coloured manuals
manpdf                                                            # Open man page as PDF
mkd                                                               # Create a new directory and enter it
msh                                                               # Open a tmux terminal inside a mosh session. Usage: msh <hostname> {session_name}
prettyjson                                                        # Pretty print json. Usage: echo {"foo": "lorem", "bar": "ipsum"} | prettyjson
pyclean                                                           # Clean all python cache files (works for both py2 and py3)
reload                                                            # Reload the shel
report_local_port_forwardings                                     # Display all local port forwarding tunnels
report_remote_port_forwardings                                    # Display all remote port forwarding tunnels
run_under_tmux                                                    # Run $1 under session or attach if such session already exist. Example usage: run_under_tmux 'htop';
shell_is_interactive                                              # Checks if shell is interactive
start_tunnel                                                      # Start an SSH connection to the first argument, while creating a tunnel for each of the remaining arguments. Example: `start_tunnel github.com 8888:127.0.0.1:27017 `
targz                                                             # Create a .tar.gz archive, using `zopfli`, `pigz` or `gzip` for compression
timer                                                             # Stopwatch to count execution time for a command. Usage example: timer ls -la
title                                                             # Set terminal titles in OSX
tsh                                                               # Open a tmux terminal inside an ssh session. Usage: tsh <hostname> {session_name}
txa                                                               # Attach to a named tmux session using iTerm2 native tmux integration.
txiterm                                                           # Attach to the default tmux session using iTerm2 native tmux integration.
update_dotfiles                                                   # Update and install latest dotfiles version
urlencode                                                         # URL-encode strings
```
