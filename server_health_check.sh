#!/usr/bin/env bash

set -euo pipefail

log_file=$(mktemp /tmp/health_server.XXXXXX)
readonly log_file

clean_up()
{
  echo "Cleaning Up Temporary Log File : $log_file"
  rm -f $log_file
}

trap clean_up EXIT INT TERM
echo "Script started. Log file created at: $log_file"

# Log an informational message to both screen and log file
log_info()
  {
    echo "[INFO] $1" | tee -a "$log_file"
  }

# Log an error message to stderr and to the log file
log_error() 
  {
    # >&2 sends the output to stderr
    echo "[ERROR] $1" | tee -a "$log_file" >&2
  }


print_usage()
 {
  echo "Usage: $0 -f <server_list_file> -u <remote_user>"
  echo " -f: Path to a file containing a list of servers (one per line)."
  echo " -u: The remote SSH user to connect as."
  echo " -h: Display this help message."
 }

check_server() {
  local server="$1"
  local user="$2"
  log_info "--- Checking Server: $server ---"

  ssh -n -o ConnectTimeout=5 "${user}@${server}" << 'EOF'
  echo "--- System Uptime ---"
  uptime

  echo "--- Disk Usage (Root /) ---"
  df -h / | awk 'NR==2 {print "Used: " $5 " (" $3 "/" $2 ")"}'

  echo "--- Memory Usage ---"
  free -m | awk 'NR==2 { printf "Used: %sMB / Total: %sMB (%.2f%%)\n", $3, $2, ($3/$2)*100 }'

  echo "--- Security (SSH) ---"
  AUTH_LOG="/var/log/auth.log"
  if [[ -f "$AUTH_LOG" ]]; then
    count=$(grep -c "Failed password" "$AUTH_LOG")
    echo "Failed SSH Attempts: $count"
  else
    echo "Failed SSH Attempts: auth log not found."
  fi
EOF

  log_info "--- Finished Check: $server ---"
}


 main()
 {
  local server_file=""
  local remote_user=""

  while getopts ":f:u:h"  opt; do
    case "$opt" in 
        f)server_file="$OPTARG";;
        u)remote_user="$OPTARG";;
        h)print_usage
          exit 0;;
       \?)log_error "Invalid Option: $OPTARG"  print_usage exit 0 ;;
       :)log_error "Option $OPTARG Required an Argument" print_usage exit 1 ;;
    esac
  done

# Validate the inputs
if [[ -z "$server_file" || -z "$remote_user" ]]; then
  log_error "Missing Required Argument!"
  print_usage
  exit 1
fi

# Check if the File exist
if [[ ! -f "$server_file" ]]; then
  log_error "Server File Not Exist $server_file"
  exit 1
fi


# List the server IPs in A Array
declare -a servers=()
while IFS= read -r line; do
  if [[ -z "$line" || "$line" == \#* ]]; then
    continue
  fi
  servers+=("$line")
done < "$server_file"

if [[ ${#servers[@]} -eq 0 ]]; then
log_error "No servers found in $server_file. Exiting."
exit 1
fi

log_info "Configuration valid. Starting health checks..."
log_info "Found ${#servers[@]} servers to check. Starting..."
# Loop through the array properly
for server_host in "${servers[@]}"; do
check_server "$server_host" "$remote_user"
done
log_info "All checks completed."

}

main "$@"

