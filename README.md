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

By default, validation checks Linux/WSL-oriented hosts (`unix`, `wsl`, and `docker`). To include every role, including macOS and zsh roles:

```bash
~/.dotfiles$ helpers/validate.sh --all-roles
```

When testing install dry-runs from a worktree, use a temporary `HOME` so existing symlinks from another checkout do not affect the result:

```bash
~/.dotfiles$ HOME="$(mktemp -d)" ./install unix --dry-run
```

## Loading source files

In order to load the dotfiles, you need to run:
```bash
~$ source ~/.bash_profile
```

## Customization

All linked files should be left as they are, unless you plan to commit changes to the dotfiles repo.

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
cleanup_ds                                                        # Recursively delete `.DS_Store` files under the current path
confirm                                                           # Confirmation wrapper. Usage: confirm rm -rf /tmp/folder
dot_progress                                                      # Fancy progress function from Landley's Aboriginal Linux. Usage: rm -rfv /foo | dot_progress
escape                                                            # Uber useful when you need to translate a weird path into single-argument string.
external_ip                                                       # Get external IP address
extract                                                           # Extra many types of compressed packages
fs                                                                # Determine size of a file or total size of a directory
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
run_under_tmux                                                    # Run $1 under session or attach if such session already exist. Example usage: run_under_tmux 'rtorrent' '/usr/local/rtorrent-git/bin/rtorrent';
shell_is_interactive                                              # Checks if shell is interactive
targz                                                             # Create a .tar.gz archive, using `zopfli`, `pigz` or `gzip` for compression
timer                                                             # Stopwatch to count execution time for a command. Usage example: timer ls -la
title                                                             # Set terminal titles in OSX
tsh                                                               # Open a tmux terminal inside an ssh session. Usage: tsh <hostname> {session_name}
update_dotfiles                                                   # Update and install latest dotfiles version
urlencode                                                         # URL-encode strings
```
