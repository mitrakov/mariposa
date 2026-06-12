#!/usr/bin/env bash
# execute dockerfile as bash (Ubuntu, root/sudo)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive        # skip shitty dialogs

# helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'
function debug() { echo -e "${PURPLE} [DEBUG] $1${NC}"; }
function log()   { echo -e "${GREEN} [LOG]   $1${NC}"; }
function info()  { echo -e "${BLUE}$ [INFO]  $1${NC}"; }
function warn()  { echo -e "${YELLOW} [WARN]  $1${NC}"; }
function error() { echo -e "${RED} [ERROR] $1${NC}"; }

# checks
function check_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
  fi
}
function check_args() {
  if [[ $# -ne 1 ]]; then
    error "Usage: $0 <dockerfile>"
    exit 2
  fi
  if [[ ! -f "$1" ]]; then
    error "File not found: $1"
    exit 3
  fi
}
function check_files() {
  while IFS= read -r line; do
    if [[ ! "$line" =~ ^COPY ]]; then
      continue
    fi
    if [[ "$line" =~ 'COPY --from' ]]; then
      continue
    fi

    local file=$(echo "$line" | awk '{print $2}')

    if [[ ! -f "$file" ]]; then
      error "Missing file from COPY command: $file"
      exit 4
    fi
  done < "$1"
}

# docker functions
function FROM() {
  # add custom code here:
  if [[ "$1" == eclipse-temurin:17 ]]; then
    apt install --yes openjdk-17-jdk wget gpg curl
    mkdir --parents /opt/hue
    ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-arm64
  else
    warn "FROM $* is ignored. Please install packages manually"
  fi
}
function RUN() {
  "$@"
}
function ENV() {
  export "$1"
  if ! grep --quiet "export $1" /etc/profile.d/mariposa.sh; then
    echo "export $1" >> /etc/profile.d/mariposa.sh
  fi
}
function COPY() {
  if [[ "$1" =~ --from.* ]]; then
    warn "COPY --from is not supported. Please do it manually"
  else
    cp -v "$@"
  fi
}
function LABEL() {
  info "LABEL $*"
}
function USER() {
  info "USER $*"     # TODO: sudo su -?
}
function ENTRYPOINT() {
  info "ENTRYPOINT $*"
}
function CMD() {
  info "CMD $*"
}



check_root
check_args "$@"
check_files "$@"
info "Welcome to docker2bash.sh. I'll help you execute $* as Bash"
sleep 2

apt update                                   # update ubuntu package manager
source /etc/profile.d/mariposa.sh || true    # export variables from prev. docker files

set -x                                       # turn debug on
source "$1"
set +x

log "Done."
