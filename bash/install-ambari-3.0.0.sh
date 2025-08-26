#!/bin/bash
set -eo pipefail  # exit on any error or pipe failure

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging functions
function log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] [LOG]   $1"
    echo -e "${GREEN}${message}${NC}"
}

function info() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]  $1"
    echo -e "${BLUE}${message}${NC}"
}

function warn() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] [WARN]  $1"
    echo -e "${YELLOW}${message}${NC}"
}

function error() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}${message}${NC}"
}

function section() {
    local message="$1"
    echo
    echo -e "${PURPLE}=================================================="
    echo -e "  ${message}"
    echo -e "==================================================${NC}"
    echo
}

# Cleanup and error handling
function handle_cleanup() {
    log "Script execution completed"
}

function handle_error() {
    local last_command="$BASH_COMMAND"
    local last_line="$LINENO"
    error "ERROR occurred on line $last_line: '$last_command' exited with status $?"
    exit 1
}

# Checks command line arguments
INPUT_FILE=""
function check_args() {
    if [[ $# -ne 1 ]]; then
        error "Usage: $0 <hosts-file>"
        echo -e "File should contain ip-to-hostname pairs:\n\nIP-address1    hostname1\nIP-address2    hostname2\n...\nIP-addressN    hostnameN\n"
        exit 2
    fi
    
    INPUT_FILE="$1"
    
    if [[ ! -f "$INPUT_FILE" ]]; then
        error "File not found: $INPUT_FILE"
        exit 3
    fi
}

# Checks if running as root
function check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 4
    fi
}

# Detects OS
function check_os() {
    local result=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        result="MacOS $(sw_vers -productVersion) (Build: $(sw_vers -buildVersion))"
    elif [[ -f /etc/os-release ]]; then
        # linux distributions with /etc/os-release
        source /etc/os-release
        result="$ID $VERSION_ID ($PRETTY_NAME)"
    elif [[ -f /etc/redhat-release ]]; then
        # fallback for older RHEL systems without /etc/os-release
        result=$(cat /etc/redhat-release)
    else
        error "Unable to detect operating system"
        exit 5
    fi

    info "OS: $result"
}

# Detects primary IPv4 address
function check_primary_ip() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - use route and ifconfig
        local primary_interface=$(route get default | grep interface | awk '{print $2}')
        ipv4_addr=$(ifconfig "$primary_interface" | grep 'inet ' | awk '{print $2}')
    else
        # Linux - use ip command
        local primary_interface=$(ip route | grep default | awk '{print $5}' | head -1)
        ipv4_addr=$(ip -4 addr show "$primary_interface" | grep inet | awk '{print $2}' | cut -d'/' -f1 | head -1)
    fi
    
    info "Default IPv4 address: $ipv4_addr"
}

# Detects hostname
function check_hostname() {
    info "Hostname: $(hostname)"
}

# Detects Python version
function check_python() {
    # check if Python is installed
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed or not found in PATH"
        exit 6
    fi
    
    # get Python version
    local python_version=$(python3 --version 2>&1)
    
    # extract version numbers (e.g., "3.9.2" from "Python 3.9.2")
    local version_number=$(echo "$python_version" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    local major=$(echo "$version_number" | cut -d. -f1)
    local minor=$(echo "$version_number" | cut -d. -f2)
    local patch=$(echo "$version_number" | cut -d. -f3)
    
    # verify if version meets minimum requirements (Python 3.6+)
    if [[ $major -eq 3 && $minor -ge 6 ]] || [[ $major -gt 3 ]]; then
        info "Python version: $version_number"
    else
        error "Python version $version_number is incompatible (3.6+ required)"
        exit 7
    fi
}

# Detects Java version
function check_java() {
    if [[ -n "${JAVA_HOME:-}" ]]; then  # :-} returns empty string instead of error
        info "JAVA_HOME: $JAVA_HOME"
    else
        warn "JAVA_HOME: not detected"
    fi

    if command -v java &> /dev/null; then
        local java_version=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    
        if [[ -n "$java_version" ]]; then
            info "Java version: $java_version"
        else
            warn "Cannot detect Java version"
        fi
    else
        warn "'java' command not found"
    fi
}

# Sets SELinux to permissive mode
function set_selinux_permissive() {
    section "SELinux configuration"

    # if getenforce == Enforcing
    setenforce 0
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

    info "SELinux done"
    sleep 1
}

# Adds entries to /etc/hosts file
function setup_hosts() {
    section "Hosts file configuration"
    
    info "Current /etc/hosts content:"
    cat /etc/hosts | tail -20
    echo

    # processing input file
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^# ]] && continue   # skip blank lines and comments

      local ip=$(echo "$line" | awk '{print $1}')
      local hostname=$(echo "$line" | awk '{print $2}')

      if grep -qE "\\b$ip\\b.*\\b$hostname\\b" /etc/hosts; then
        info "Entry for $ip $hostname already exists. Skipping."
      else
        echo "$ip $hostname" >> /etc/hosts
        log "Added: $ip $hostname"
      fi
    done < "$INPUT_FILE"

    info "Now /etc/hosts content:"
    cat /etc/hosts | tail -20
    echo
}

# Disables firewall
function disable_firewall() {
    section "Firewall configuration"

    if systemctl is-active --quiet firewalld; then
        systemctl stop firewalld && systemctl disable firewalld
        info "Firewall disabled"
        sleep 1
    else
        info "Firewall is already inactive"
    fi
}

# Installs JDK 1.8 and JDK 17
function install_java() {
    # we need Java8 and Java17 for all nodes! Ambari/Hive require java17; HDFS/Kafka require Java8; also no symlinks allowed;
    # WARNING: JCE Policy files are required for configuring Kerberos security. If you plan to use Kerberos,please make sure JCE Unlimited Strength Jurisdiction Policy Files are valid on all hosts.
    section "JDK installation"

    # Install Sdkman
    if [[ ! -d "/root/.sdkman" ]]; then
        dnf install -y zip unzip tar
        curl https://get.sdkman.io | bash
    else
        info "SdkMan already installed"
    fi

    source "/root/.sdkman/bin/sdkman-init.sh"

    sdk install java 17.0.16-amzn
    sdk install java 8.0.462-amzn

    info "Java installations are completed"
}

# Copy Java installations
# must NOT contain symlinks!
# must NOT be in protected folder (/root)
function copy_java() {
    section "Copy JDKs"
    local jdk8="/usr/lib/jdk8"
    local jdk17="/usr/lib/jdk17"

    log "Copying Java installations to /usr/lib"

    # copy Java 17
    if [[ -d "/root/.sdkman/candidates/java/17.0.16-amzn" ]]; then
        if [[ ! -d "$jdk17" ]]; then
            cp -r "/root/.sdkman/candidates/java/17.0.16-amzn" "$jdk17"
            log "Java 17 copied to $jdk17"
        else
            info "Directory $jdk17 already exists, skipping..."
        fi
    else
        error "Java 17 installation not found"
    fi

    # copy Java 8
    if [[ -d "/root/.sdkman/candidates/java/8.0.462-amzn" ]]; then
        if [[ ! -d "$jdk8" ]]; then
            cp -r "/root/.sdkman/candidates/java/8.0.462-amzn" "$jdk8"
            log "Java 8 copied to $jdk8"
        else
            info "Directory $jdk8 already exists, skipping..."
        fi
    else
        error "Java 8 installation not found"
    fi
}

# Configures BigTop repository
function setup_ambari_repo() {
    section "Ambari Repository configuration"

    if [[ ! -f "/etc/yum.repos.d/ambari.repo" ]]; then
        check_hostname
        check_primary_ip
        read -p "Enter the repository URL (e.g. http://192.168.1.1/ambari-repo): " ambari_repo
        if [[ -n "$ambari_repo" && "$ambari_repo" =~ ^http ]]; then
            log "Creating file /etc/yum.repos.d/ambari.repo. Setting up Ambari repository to: $ambari_repo"

            cat > /etc/yum.repos.d/ambari.repo << EOF
[ambari]
name=Ambari Repository
baseurl=$ambari_repo
gpgcheck=0
enabled=1
EOF
            info "Ambari repository configured to: $ambari_repo"
        else
            error "Repository URL should start with 'http' or 'https'"
            exit 8
        fi
    else
        info "Ambari repository is already configured"
        sleep 1
    fi
}

# Installs Ambari-Server
function install_ambari_server() {
    dnf install -y ambari-server
}

# Configures MySQL JDBC connector for Hive
function setup_mysql_jdbc() {
    section "Download MySQL JDBC connector for Hive"

    dnf install -y wget
    wget https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/9.3.0/mysql-connector-j-9.3.0.jar
    ambari-server setup --jdbc-db=mysql --jdbc-driver=mysql-connector-j-9.3.0.jar
}

# Launches Ambari-Server
function start_ambari_server() {
    section "Starting Ambari-Server"

    ambari-server setup --java-home /usr/lib/jdk8 --ambari-java-home /usr/lib/jdk17 --stack-java-home /usr/lib/jdk8
    ambari-server start    # admin/admin; for services: root/admin7777
}

# Applies bug fixes for agents
function apply_agent_fixes() {
    section "Applying agent fixes"

    # Error: "package 'distro' not found"
    dnf install -y python3-distro
    info "Fix 1 done"

    # Error: "Error unpacking rpm package chkconfig-1.24-2.el9.x86_64"
    dnf install -y chkconfig    # if you already have this error run: rm -rf /etc/init.d
    info "Fix 2 done"

    # Error: "nothing provides redhat-lsb needed by ranger_3_3_0-admin-2.4.0-1.el9.x86_64 from ambari'"
    dnf config-manager --set-enabled devel
    info "Fix 3 done"

    # Error: "JAVA_HOME is not set, and java command not found"
    echo "export JAVA_HOME=/usr/lib/jdk8" >> /etc/profile
    info "Fix 4 done"

    info "Agent fixes applied"
}

# Applies fix for HDFS-Router error: "The package hadoop-hdfs-dfsrouter is not supported by this version of the stack-select tool"
function patch_distro_select() {
    section "HDFS Router bug fix"

    local distro_select_file="/usr/lib/bigtop-select/distro-select"
    local new_entry='           "hadoop-hdfs-dfsrouter": "hadoop-hdfs",'
    local insert_after='           "hadoop-hdfs-zkfc": "hadoop-hdfs",' # insert after this line

    # check if the distro-select.py file exists
    if [ ! -f "$distro_select_file" ]; then
        error "Error: file $distro_select_file not found. Probably Ambari-Server hasn't installed it yet"
        error "First, start cluster deployment and then wait a while"
        exit 9
    fi

    # check if the entry already exists to prevent duplicate additions
    if grep -qF "$new_entry" "$distro_select_file"; then
        warn "Entry '$new_entry' already exists in $distro_select_file. Skipping patch..."
        return 0
    fi

    # process update
    sed -i "/$insert_after/a\\$new_entry" "$distro_select_file" # 'a\' appends text after the matched line

    if [ $? -eq 0 ]; then
        info "Successfully added '$new_entry' to $distro_select_file."
        info "Verification (showing 2 lines around the change):"
        grep -B 2 -A 2 -F "$new_entry" "$distro_select_file"
    else
        error "Error: Failed to patch $distro_select_file. Please check the file manually!"
        exit 10
    fi
}

# Common code for Ambari-Server and Ambari agents
function install_common() {
    set_selinux_permissive
    setup_hosts
    disable_firewall
    install_java
    copy_java
}

# Installs Ambari-Server
function install_server() {
    section "Install Ambari-Server"

    install_common
    sdk default java 17.0.16-amzn
    setup_ambari_repo
    install_ambari_server
    setup_mysql_jdbc
    start_ambari_server
}

# Installs Ambari agent
function install_agent() {
    section "Install Ambari agent"

    install_common
    sdk default java 8.0.462-amzn
    apply_agent_fixes
}

# Checks for user choice
function get_user_choice() {
    while true; do
        read -p "Please select an option [1-4]: " choice
        case $choice in
            [1-4]) break ;;
            *) ;;
        esac
    done
    echo "$choice"
}

# Main function
function main() {
    section "Ambari-Server installation script"
    info "by Artem Mitrakov (mitrakov-artem@yandex.ru) 2025"

    while true; do
        section "My Installation Menu"
        echo "1. Install Ambari-Server"
        echo "2. Install Ambari-Agent"
        echo "3. Fix error: The package hadoop-hdfs-dfsrouter is not supported"
        echo "4. Exit"
        echo
        
        local choice=$(get_user_choice)
        
        case $choice in
            1)
                install_server
                break
                ;;
            2)
                install_agent
                break
                ;;
            3)
                patch_distro_select
                break
                ;;
            4)
                exit 0
                ;;
        esac
    done
}

check_args "$@"
check_root
check_os
check_primary_ip
check_hostname
check_python
check_java

trap handle_cleanup EXIT
trap handle_error   ERR

main "$@"
