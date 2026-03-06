# Display all local port forwarding tunnels
function report_local_port_forwardings() {

  # -a ands the selection criteria (default is or)
  # -i4 limits to ipv4 internet files
  # -P inhibits the conversion of port numbers to port names
  # -c /regex/ limits to commands matching the regex
  # -u$USER limits to processes owned by $USER
  # http://man7.org/linux/man-pages/man8/lsof.8.html
  # https://stackoverflow.com/q/34032299

  LOCAL_PORTS_FORWARDED=`lsof -a -i4 -P -c '/^ssh$/' -u$USER -s TCP:LISTEN`
  if [ -z "$LOCAL_PORTS_FORWARDED" ]; then
    echo "No local port forwardings found"
    return 0
  fi

  echo
  echo "LOCAL PORT FORWARDING"
  echo
  echo "You set up the following local port forwardings:"
  echo

  echo "$LOCAL_PORTS_FORWARDED"

  echo
  echo "The processes that set up these forwardings are:"
  echo

  ps -f -p $(lsof -t -a -i4 -P -c '/^ssh$/' -u$USER -s TCP:LISTEN)

}

# Display all remote port forwarding tunnels
function report_remote_port_forwardings() {

  REMOTE_PORTS_FORWARDED=`ps -f -p $(lsof -t -a -i -c '/^ssh$/' -u$USER -s TCP:ESTABLISHED) | awk 'NR == 1 || /R (\S+:)?[[:digit:]]+:\S+:[[:digit:]]+.*/'`
  if [[ -n "${REMOTE_PORTS_FORWARDED// /}" ]]; then
    echo "No remote port forwardings found"
    return 0
  fi
  echo
  echo "REMOTE PORT FORWARDING"
  echo
  echo "You set up the following remote port forwardings:"
  echo

  echo "$REMOTE_PORTS_FORWARDED"
}