#!/bin/bash
set -eo pipefail  # exit on any error or pipe failure

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'
INPUT_FILE=""

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
    echo
    log "Good bye, dude!"
}

function handle_error() {
    local last_command="$BASH_COMMAND"
    local last_line="$LINENO"
    error "ERROR occurred on line $last_line: '$last_command' exited with status $?"
    exit 1
}

# Check command line arguments
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

# Check if running as root
function check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 4
    fi
}

# Detect OS
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

# Detect primary IPv4 address
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

# Detect hostname
function check_hostname() {
    info "Hostname: $(hostname)"
}

# Detect Python version
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

# Detect Java version
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

# Check package manager
function check_dnf() {
    if ! command -v dnf &> /dev/null; then
        error "DNF not found. Make sure your OS is RHEL compatible (CentOS, Rocky)"
        exit 8
    fi
}








# Upgrade SSH libraries
function update_ssh() {
    section "SSL/SSH Configuration"

    info "Current OpenSSL version:"
    openssl version

    info "You may encounter login issues if your OpenSSL is outdated, because Ambari may update it during its own installation"
    read -p "Update SSH components? (recommended) (Y/n): " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        log "Updating SSH components..."

        dnf install -y openssl openssh-server openssh-clients

        info "New OpenSSL version:"
        openssl version
    fi
}

# Setup hostname
function setup_hostname() {
    section "Hostname Configuration"

    # TODO: if already changed?

    info "Let's update our hostname. This step is completely optional"
    cat $INPUT_FILE
    check_hostname
    check_primary_ip

    read -p "Enter new hostname (press ENTER to skip): " hostname
    if [[ -n "$hostname" ]]; then
        hostnamectl set-hostname "$hostname"
        check_hostname
    else
        info "Hostname unchanged"
    fi

    sleep 1
}

# Setup hosts file with predefined entries
function setup_hosts() {
    section "Hosts File Configuration"
    
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

# Disables Firewall
function disable_firewall() {
    section "Firewall Configuration"

    if systemctl is-active --quiet firewalld; then
        info "It's highly recommended to disable firewall and enable it only in PROD after cluster deployment"
        read -p "Disable firewall? (recommended) (Y/n): " -r
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            log "Disabling firewall..."

            systemctl stop firewalld && systemctl disable firewalld
            log "Firewall disabled successfully"
        fi
    else
        info "Firewall is already inactive"
    fi
}

# Install Java using SdkMan!
install_java() {
    section "Java Installation"

    log "Installing Java using Sdkman..."

    # Install Sdkman
    if [[ ! -d "/root/.sdkman" ]]; then
        dnf install -y zip unzip tar
        curl https://get.sdkman.io | bash
        log "SdkMan installed"
    else
        info "SdkMan already installed"
    fi

    source "/root/.sdkman/bin/sdkman-init.sh"

    # Install Java versions
    log "Installing Java 17..."
    sdk install java 17.0.16-amzn

    log "Installing Java 8..."
    sdk install java 8.0.462-amzn

    # Set Java 8 as default
    sdk default java 8.0.462-amzn

    info "Java installations are completed"
}

# Copy Java installations (must NOT contain symlinks!)
function copy_java() {
    section "Copy JDKs"
    local jdk8="/usr/jdk64/jdk8"
    local jdk17="/usr/jdk64/jdk17"

    log "Copying Java installations to /usr/jdk64"

    mkdir -p /usr/jdk64

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

# Verify Java installations
function verify_java() {
    section "Verifying Java installations..."

    if [[ -x "/usr/jdk64/jdk8/bin/java" ]] && [[ -x "/usr/jdk64/jdk17/bin/java" ]]; then
        info "Java 8 version:"
        /usr/jdk64/jdk8/bin/java -version

        info "Java 17 version:"
        /usr/jdk64/jdk17/bin/java --version
    else
        error "Java installations not found or not executable"
    fi
}

# Common logic for server and agents
function common_setup() {
    update_ssh
    fix_selinux
    setup_hostname
    setup_hosts
    disable_firewall
    install_java
    copy_java
    verify_java

    info "Common setup completed successfully"
}

# Configure Ambari repository
function setup_ambari_repo() {
    section "Ambari Repository Configuration"

    if [[ ! -f "/etc/yum.repos.d/ambari.repo" ]]; then
        check_hostname
        check_primary_ip
        read -p "Enter the repository URL (e.g. http://192.168.1.1/ambari-repo): " ambari_repo
        if [[ -n "$ambari_repo" && "$ambari_repo" =~ ^http ]]; then
            log "Setting up Ambari repository to: $ambari_repo"
            log "Creating file /etc/yum.repos.d/ambari.repo"

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
            exit 9
        fi
    else
        info "Ambari repository is already configured"
        sleep 1
    fi
}

# Install Ambari Server
function install_ambari_server() {
    section "Ambari Server Installation"

    dnf install -y ambari-server
}

# Setup Ambari Server
function setup_ambari_server() {
    log "Setting up Ambari-Server with Java configurations..."

    # TODO check if needed

    ambari-server setup \
        --java-home /usr/jdk64/jdk8 \
        --ambari-java-home /usr/jdk64/jdk17 \
        --stack-java-home /usr/jdk64/jdk8

    info "Ambari Server setup completed"
}

# Setup MySQL connector for Ambari-Server
function setup_mysql_connector() {
    info "If you want to use Hive with MySQL you need to register MySQL JDBC driver"

    # TODO check if already installed

    read -p "Setup MySQL connector for Hive (recommended)? (Y/n): " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        log "Downloading and setting up MySQL connector..."

        local file="mysql-connector-j-9.3.0.jar"
        local url="https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/9.3.0/$file"

        dnf install -y wget
        wget -q "$url"

        if [[ -f "$file" ]]; then
            ambari-server setup --jdbc-db=mysql --jdbc-driver="$file"
            info "MySQL connector setup completed"
        else
            error "Failed to download MySQL connector: $url"
        fi
    fi
}

function start_ambari_server() {
    log "Starting Ambari Server..."

    # TODO check if started

    ambari-server start

    info "Access Ambari Web UI at: http://$(hostname):8080"
    info "Default credentials: admin/admin"
}

function install_lsb_packages() {
    # TODO check if exists?
    # TODO: tmp folder?

    log "Downloading LSB packages..."
    dnf install -y wget
    local file1="spax-1.6-7.gf.el9.x86_64.rpm"
    local file2="redhat-lsb-submod-security-4.1-59.1.gf.el9.x86_64.rpm"
    local file3="redhat-lsb-core-4.1-59.1.gf.el9.x86_64.rpm"
    local url1="https://mirror.ghettoforge.net/distributions/gf/el/9/gf/x86_64/$file1"
    local url2="https://mirror.ghettoforge.net/distributions/gf/el/9/gf/x86_64/$file2"
    local url3="https://mirror.ghettoforge.net/distributions/gf/el/9/gf/x86_64/$file3"
    wget -q "$url1"
    wget -q "$url2"
    wget -q "$url3"

    log "Installing LSB packages..."
    dnf install -y "$file1"
    dnf install -y "$file2"
    dnf install -y "$file3"
}

# Installs extra packages for Ambari-Client
function install_extra_packages() {
    section "Installing missing packages and bug fixes"

    # Fix 1:
    log "Fix 1: ModuleNotFoundError: No module named 'distro'"
    dnf install -y python3-distro
    info "python3-distro installed successfully"

    # Fix 2:
    # Root cause: package libtirpc-devel resides in CRB repo which is disabled by default
    log "Fix 2: dnf libtirpc-devel not found"
    dnf config-manager --set-enabled crb || info "CRB repository may already be enabled"
    info "CRB repository configuration completed"

    # Fix 3:
    # Root cause: RHEL-9 removed LSB packages at all
    log "Fix 3: nothing provides /lib/lsb/init-functions needed by hadoop_3_3_0"
    install_lsb_packages
    info "LSB packages installed successfully"

    # Fix 4:
    # Root cause: /etc/init.d should be a symlink to "rc.d/init.d", but Ambari creates a new directory instead.
    # As a result, package "chkconfig" fails to install. So let's install chkconfig manually, it will create a synlink.
    log "Fix 4: Error unpacking rpm package chkconfig-1.24-2.el9.x86_64"
    dnf install -y chkconfig
    info "chkconfig installed successfully"

    info "All extra packages have been installed successfully"
    echo
}

# Fix error on re-login: PAM: pam_open_session(): Error in service module
# Fix error: Nginx cannot see files in /var/www/html
function fix_selinux() {
    log "Switching SELinux to permissive mode, to avoid possible issues with PAM modules on re-login"

    # update current boot
    if [ setenforce 0 ]; then
      info "SELinux set to 0"
    fi

    # make permanent
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

    info "SELinux configuration done..."
}

# Sets JAVA_HOME to Java-8 for agents
function set_java_home() {
    # essentially this is only needed for 1 Ambari-Agent running Kafka-Broker, which fails during installation with:
    # Cannot execute "/usr/bigtop/current/kafka-broker/bin/kafka-run-class.sh": java not found.
    # For all other agents JAVA_HOME is propagated by Ambari automatically

    local java_home_path="/usr/jdk64/jdk8"
    local profile_script="/etc/profile.d/java_home.sh"

    # check if JAVA_HOME is already set in any of the profile.d scripts
    if grep -r "export JAVA_HOME=" /etc/profile.d/ | grep -q "$java_home_path"; then
        info "JAVA_HOME is already set to $java_home_path in /etc/profile.d/. Skipping..."
    else
        log "Creating script to set JAVA_HOME..."

        cat > $profile_script << EOF
#!/bin/sh
export JAVA_HOME=$java_home_path
EOF
        chmod +x "$profile_script"

        info "Script created and made executable: $profile_script"
        info "For Ambari, no need to reboot the system. However for you, re-login is required to see new JAVA_HOME"
    fi
}


# Install server: main function
function install_server() {
    common_setup
    setup_ambari_repo
    install_ambari_server
    setup_ambari_server
    setup_mysql_connector
    start_ambari_server

    info "Server Installation Completed"
}

# Install agent: main function
function install_agent() {
    common_setup
    install_extra_packages
    set_java_home

    info "Agent Installation Completed"
    info "Make sure to configure passwordless root SSH key on each agent"
    echo
    warn "If you see an error: 'The package hadoop-hdfs-dfsrouter is not supported by this version of the stack-select tool'"
    warn "Run this script again with option '4'"
}

# Install repository
function install_repo() {
  section "Installing repository"
  info "It's totally OK to setup repository along with Ambari-Server"
  local dir=/var/www/html/ambari-repo

  fix_selinux

  log "Installing createrepo"
  dnf install -y createrepo
  mkdir -p "$dir"
  cd $dir

  log "Downloading packages"
  local url1="https://www.apache-ambari.com/dist/ambari/3.0.0/rocky9/"
  local url2="https://www.apache-ambari.com/dist/bigtop/3.3.0/rocky9/"
  read -p "Download Ambari/Bigtop packages (≈7.25 Gb)? If not, copy them manually to $dir. (Y/n): " -r
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      log "Downloading packages (≈7.25 Gb). It may take some time..."
      dnf install -y wget
      wget -r -np -nH --cut-dirs=4 --reject 'index.html*' "$url1"
      wget -r -np -nH --cut-dirs=4 --reject 'index.html*' "$url2"
  fi

  if [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ]; then
    error "Directory $dir is empty. Please download or copy Ambari and Bigtop packages there"
    info "$url1"
    info "$url2"
    exit 13
  fi

  log "Creating local repository"
  cd /var/www/html && createrepo .

  log "Installing nginx"
  dnf install -y nginx
  cat > /etc/nginx/conf.d/ambari-repo.conf << EOF
server {
    listen 80;
    server_name _;
    root /var/www/html;
    autoindex on;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

  log "Let's open port 80"
  if systemctl is-active --quiet firewalld; then
    log "Firewall is enabled, adding rule for 80/tcp"
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --reload
    info "Done..."
  else
    info "Firewall is disabled, skipping"
  fi

  # SELinux fix
  if [ "$(getenforce)" = "Enforcing" ]; then
    log "SELinux is Enforcing. Applying chcon..."
    chcon -R -t httpd_sys_content_t    /var/www/html/
    chcon -R -t httpd_sys_rw_content_t /var/www/html/
    echo "Done: Applied SELinux context"
  else
    info "SELinux is not Enforcing..."
  fi

  log "Starting nginx..."
  systemctl start nginx && systemctl enable nginx

  log "Validating URL..."
  curl -s localhost > /dev/null && info "Nginx is setup for Ambari repository"
}

# This addresses the HDFS-Router error: "The package hadoop-hdfs-dfsrouter is not supported".
function patch_distro_select() {
    local distro_select_file="/usr/lib/bigtop-select/distro-select"
    local new_entry='           "hadoop-hdfs-dfsrouter": "hadoop-hdfs",'
    local insert_after='           "hadoop-hdfs-zkfc": "hadoop-hdfs",' # insert after this line

    log "Attempting to patch $distro_select_file..."

    # check if the distro-select.py file exists
    if [ ! -f "$distro_select_file" ]; then
        error "Error: file $distro_select_file not found. Probably Ambari-Server hasn't installed it yet"
        error "First, start cluster deployment and then wait a while"
        exit 11
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
        exit 12
    fi
}








# Get user choice
function get_user_choice() {
    while true; do
        read -p "Please select an option [1-5]: " choice
        case $choice in
            [1-5]) break ;;
            *) ;;
        esac
    done
    echo "$choice"
}

# Main function
function main() {
    section "Ambari Installation Script"
    info "by Artem Mitrakov (mitrakov-artem@yandex.ru) 2025"
    info "Requirements: OS redhat9 (CentOS, Rocky); Python 3.6+"
    info "Install Ambari-Server and (optinally) repository to one dedicated node, and Ambari-Agents to all other nodes"
    info "For agents, minimum 3 nodes are required (2 masters and the rest for data nodes)"
    info "Make sure to have passwordless root SSH access to all nodes in the network"
    info "All these nodes should have normal unique hostnames and be reflected in your hosts file: $INPUT_FILE"
    
    log "Start Ambari installation process"
    
    while true; do
        section "Ambari Installation Menu"
        echo "1. Install Ambari-Server"
        echo "2. Install Ambari-Agent"
        echo "3. Install repository (may be installed along with Ambari-Server)"
        echo "4. Install patch for HDFS-Router (needed for all agents after cluster deployment start)"
        echo "5. Exit"
        echo
        
        local choice=$(get_user_choice)
        
        case $choice in
            1)
                log "Selected: Install Ambari-Server"
                install_server
                break
                ;;
            2)
                log "Selected: Install Ambari-Agent"
                install_agent
                break
                ;;
            3)
                log "Selected: Install repository"
                install_repo
                break
                ;;
            4)
                log "Selected: Install patch for HDFS-Router"
                patch_distro_select
                break
                ;;
            5)
                log "Selected: Exit"
                exit 0
                ;;
        esac
    done
    
    info "Installation completed successfully!"
}

# Script execution starts here
check_args "$@"
check_root
check_os
check_primary_ip
check_hostname
check_python
check_java
check_dnf
trap handle_cleanup EXIT
trap handle_error   ERR

main "$@"
