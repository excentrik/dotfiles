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

```bash
clear_cache 	 # Command to clear symfony cache. Usage: clear_cache dev
clear_db_local 	 # Command to clear the local database
clear_db_test 	 # Command to clear the test database
clear_local_env 	 # Command to clear the local environment (database+cache)
clear_test_env 	 # Command to clear the test environment (database+cache)
confirm 	 # Confirmation wrapper. Usage: confirm rm -rf /tmp/folder
dot_progress 	 # Fancy progress function from Landley's Aboriginal Linux. Usage: rm -rfv /foo | dot_progress
escape 	 # Uber useful when you need to translate a weird path into single-argument string.
extract 	 # Extra many types of compressed packages
fs 	 # Determine size of a file or total size of a directory
getHostIp 	 # Get the IP of the host inside a Docker container
get_ip_address 	 # Get the IP address of a known host. Usage: get_ip_address dev-london.rohea.com
get_ssh_hosts 	 # Get a list of all known ssh hosts
is_running_inside_container 	 # Detect if this command is running inside a docker container
kill_processes 	 # Kill all process that match the arguments
la='command ls -laF ${colorflag}' 	 # List all files colorized in long format, including dot files
list_dotfiles_functions 	 # List all function available in a shell
list_open_tunnels 	 # Function to show all open ssh connections/tunnels
ll='ls -lv --group-directories-first' 	 # Alias to use GNU ls and print directories first, with alphanumeric sorting
load_aliases 	 # Function that loads all bash aliases. Can be used in non-interactive mode
mkd 	 # Create a new directory and enter it
php_console 	 # Detect and run symfony's console
php_version 	 # Get the PHP version currently running
prettyjson='python -m json.tool' 	 # Pretty print json. Usage: echo '{"foo": "lorem", "bar": "ipsum"}' | prettyjson
pyclean 	 # Clean all python cache files (works for both py2 and py3)
reload 	 # Reload the shel
restart_phpfpm 	 # Command to restart php-fpm
run_all_tests 	 # Command to run all tests with default configuration, including stats and integration (run through composer)
run_tests 	 # Command to run tests with default configuration (run through composer)
run_under_tmux 	 # Run $1 under session or attach if such session already exist. Example usage: run_under_tmux 'rtorrent' '/usr/local/rtorrent-git/bin/rtorrent';
run_verbose_tests 	 # Command to run tests with debug configuration (run through composer)
shell_is_interactive 	 # Checks if shell is interactive
ssh_to_address 	 # Ssh to a specific host from the list of available hosts using the username define in $GITLAB_USERNAME. Usage: ssh_to_address dev-london.rohea.com
ssh_tunnel_fenad_tiatest_http 	 # Tunnel localhost:8010 to tiatest.fenad.local: through ITE
ssh_tunnel_ite 	 # Create tunnels to ITE (Mongo, TIA, and YFE API HTTP/HTTPS)
ssh_tunnel_kotikokki 	 # Create tunnels to Kotikokki (Mongo:7777, SQL:6666, and SOLR:8983)
ssh_tunnel_london 	 # Tunnel all traffic to Lodon databases (Mongo:7777,SQL:6666) (DEPRECATED)
ssh_tunnel_rohea_mongo 	 # Tunnel all traffic to mongo database dev helsinki through port 7777
ssh_tunnel_ste 	 # Create tunnels to STE (Mongo, TIA, and YFE API HTTP/HTTPS)
ssh_tunnel_yfe_api_https_testing 	 # Tunnel all traffic to STE API (yfe) through port 8443 https
ssh_tunnel_yfe_api_https 	 # Tunnel all traffic to ITE API (yfe) through port 8443 https
ssh_tunnel_yfe_api_http_testing 	 # Tunnel all traffic to STE API (yfe) through port 8080 http
ssh_tunnel_yfe_api_http 	 # Tunnel all traffic to ITE API (yfe) through port 8080 http
ssh_tunnel_yfe_mongo_testing 	 # Tunnel all traffic to mongo database fennia testing (STE) through port 8888
ssh_tunnel_yfe_mongo 	 # Tunnel all traffic to mongo database fennia beta (ITE) through port 8888
ssh_using_stanley 	 # SSH to a specific server using stanley user in stackstorm.rohea.com
start_tunnel 	 # Start an ssh tunnel to the first argument and create tunnels for each of the remaining parameters
targz 	 # Create a .tar.gz archive, using `zopfli`, `pigz` or `gzip` for compression
timer 	 # Stopwatch to count execution time for a command. Usage example: timer ls -la
tsh 	 # Open a tmux terminal inside an ssh session. Usage: tsh <hostname> {session_name}
turbo_mode_disable 	 # Command to disable turbo mode. Disables OPCACHE and enables debug mode
turbo_mode_enable 	 # Command to enable turbo mode. Enables OPCACHE and disables debug mode
turbo_mode_refresh='restart_phpfpm' 	 # Command to make sure turbo mode is refreshed
update_dotfiles 	 # Update and install latest dotfiles version
urlencode='python -c "import sys, urllib as ul; print ul.quote_plus(sys.argv[1]);"' 	 # URL-encode strings
xdebug_disable 	 # Disable xdebug
xdebug_enable 	 # Enable xdebug
xdebug_is_enabled 	 # Checks if xdebug is enabled (returns 0 for no and 1 for yes)```
