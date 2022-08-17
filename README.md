# Dotfiles

Dotfile management using [Dotbot](https://github.com/anishathalye/dotbot).

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
```

For installing a specific host:

```bash
~/.dotfiles$ ./install <host> [<roles...>]
# see meta/hosts/ for available hosts
# see meta/roles/ for available roles
```

For installing a single role/package:

```bash
~/.dotfiles$ ./install-role <roles...>
# see meta/roles/ for available roles
```

If you don't want dotfiles to ask for any user input, you can use the `DOTFILES_NO_INTERACTIVE` flag, such as:
```bash
~/.dotfiles$ DOTFILES_NO_INTERACTIVE=1 ./install
```

You can run these installation commands safely multiple times, if you think that helps with better installation.

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

## TODO

  - Implement OSX packages (xcode)
  - Windows ???
  - install roles according to host (osx - use brew to install packages, unix - use apt-get)
  - Make sure backups are done correctly
  - Add a copy plugin to dotbot
  - First time starting vi opens two buffer windows

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
kill_processes                                                    # Kill all process that match a pattern (`kill_processes ssh` kills all processes that contain ssh in their CMD string
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
