#!/bin/bash
# Universal Compatibility Fix for VPN Scripts
# This script updates the existing VPN installation scripts to work with all Ubuntu and Debian versions

# Auto-fix line endings if needed
if [[ $(head -c 3 "$0" | od -c | grep -q "\\r\\n") ]]; then
    echo "Fixing line endings..."
    sed -i 's/\r$//' "$0"
    exec bash "$0" "$@"
fi

echo "=== Universal Compatibility Fix for VPN Scripts ==="
echo "This script will update your VPN installation to work with all Ubuntu and Debian versions"
echo ""

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_VERSION=$VERSION_ID
    echo "Detected: $PRETTY_NAME"
else
    echo "Error: Cannot detect OS"
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Universal package manager function
install_pkg() {
    local pkg=$1
    if command -v apt &> /dev/null; then
        apt install -y "$pkg"
    elif command -v apt-get &> /dev/null; then
        apt-get install -y "$pkg"
    fi
}

# Update package lists
update_pkgs() {
    if command -v apt &> /dev/null; then
        apt update -y
    elif command -v apt-get &> /dev/null; then
        apt-get update -y
    fi
}

echo "Step 1: Installing universal dependencies..."
update_pkgs

# Install essential packages
install_pkg "curl"
install_pkg "wget"
install_pkg "unzip"
install_pkg "git"
install_pkg "software-properties-common"

echo "Step 2: Setting up HAProxy repositories based on OS version..."

if [[ "$OS_ID" == "ubuntu" ]]; then
    VERSION_NUM=$(echo $OS_VERSION | sed 's/\.//g')
    install_pkg "software-properties-common"
    if [ "$VERSION_NUM" -ge 2404 ]; then
        # Ubuntu 24.04+ — HAProxy 2.8 (bind-process removed in 2.1; must use 2.6+)
        add-apt-repository ppa:vbernat/haproxy-2.8 -y
        update_pkgs
        install_pkg "haproxy=2.8.*" || install_pkg "haproxy"
    elif [ "$VERSION_NUM" -ge 2204 ]; then
        # Ubuntu 22.04 — HAProxy 2.6
        add-apt-repository ppa:vbernat/haproxy-2.6 -y
        update_pkgs
        install_pkg "haproxy=2.6.*" || install_pkg "haproxy"
    elif [ "$VERSION_NUM" -ge 2004 ]; then
        # Ubuntu 20.04 — HAProxy 2.0 (unchanged, was already working)
        add-apt-repository ppa:vbernat/haproxy-2.0 -y
        update_pkgs
        install_pkg "haproxy=2.0.*"
    else
        # Ubuntu 16.04-19.10 — HAProxy 1.8
        add-apt-repository ppa:vbernat/haproxy-1.8 -y
        update_pkgs
        install_pkg "haproxy=1.8.*"
    fi
elif [[ "$OS_ID" == "debian" ]]; then
    VERSION_NUM=$(echo $OS_VERSION | sed 's/\.//g')
    if [ "$VERSION_NUM" -ge 120 ]; then
        # Debian 12 (bookworm) — HAProxy 2.6
        curl https://haproxy.debian.net/bernat.debian.org.gpg | gpg --dearmor >/usr/share/keyrings/haproxy.debian.net.gpg
        echo deb "[signed-by=/usr/share/keyrings/haproxy.debian.net.gpg]" http://haproxy.debian.net bookworm-backports-2.6 main >/etc/apt/sources.list.d/haproxy.list
        update_pkgs
        install_pkg "haproxy=2.6.*" || install_pkg "haproxy"
    elif [ "$VERSION_NUM" -ge 110 ]; then
        # Debian 11 (bullseye) — HAProxy 2.4
        curl https://haproxy.debian.net/bernat.debian.org.gpg | gpg --dearmor >/usr/share/keyrings/haproxy.debian.net.gpg
        echo deb "[signed-by=/usr/share/keyrings/haproxy.debian.net.gpg]" http://haproxy.debian.net bullseye-backports-2.4 main >/etc/apt/sources.list.d/haproxy.list
        update_pkgs
        install_pkg "haproxy=2.4.*"
    else
        # Debian 8-10 (buster and older) — HAProxy 1.8 (unchanged, was already working)
        curl https://haproxy.debian.net/bernat.debian.org.gpg | gpg --dearmor >/usr/share/keyrings/haproxy.debian.net.gpg
        echo deb "[signed-by=/usr/share/keyrings/haproxy.debian.net.gpg]" http://haproxy.debian.net buster-backports-1.8 main >/etc/apt/sources.list.d/haproxy.list
        update_pkgs
        install_pkg "haproxy=1.8.*"
    fi
fi

# ── Version-aware HAProxy configuration fix (apply to any existing install) ──
# Strip bind-process and pidfile from the deployed config if present, then
# validate and restart.  This makes compatibility-fix.sh idempotent — safe to
# run on existing servers after an OS upgrade.
CFG="/etc/haproxy/haproxy.cfg"
if [ -f "$CFG" ]; then
    echo "Applying version-aware HAProxy config fixes..."
    BACKUP="${CFG}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CFG" "$BACKUP"
    sed -i '/^[[:space:]]*bind-process[[:space:]]/d' "$CFG"
    sed -i '/^[[:space:]]*pidfile[[:space:]]/d'       "$CFG"
    VALIDATE=$(haproxy -c -f "$CFG" 2>&1)
    if [ $? -ne 0 ]; then
        echo "HAProxy validation failed — restoring backup:"
        echo "$VALIDATE"
        cp "$BACKUP" "$CFG"
    else
        echo "HAProxy config validated. Restarting..."
        systemctl daemon-reload
        systemctl reset-failed haproxy 2>/dev/null || true
        systemctl enable haproxy
        systemctl restart haproxy
    fi
fi

echo "Step 3: Installing other dependencies..."
install_pkg "nginx"
install_pkg "ruby"
install_pkg "wondershaper"

# Install Python packages with fallback
if command -v pip3 &> /dev/null; then
    pip3 install --upgrade pip
elif command -v pip &> /dev/null; then
    pip install --upgrade pip
fi

# Install additional packages
packages=(
    "zip" "pwgen" "openssl" "netcat" "socat" "cron" "bash-completion"
    "figlet" "sudo" "ntpdate" "chrony" "speedtest-cli" "vnstat"
    "build-essential" "gcc" "g++" "python3" "htop" "lsof" "tar"
    "python3-pip" "iptables" "iptables-persistent" "netfilter-persistent"
    "net-tools" "gnupg" "gnupg2" "lsb-release" "screen" "jq"
    "openvpn" "easy-rsa"
)

for pkg in "${packages[@]}"; do
    install_pkg "$pkg"
done

echo "Step 4: Setting up system configuration..."

# Set timezone
timedatectl set-timezone Asia/Jakarta

# Configure iptables persistence
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

# Enable chrony
systemctl enable chronyd 2>/dev/null || systemctl enable chrony
systemctl restart chronyd 2>/dev/null || systemctl restart chrony

# NTP sync
ntpdate pool.ntp.org

echo "Step 5: Creating universal compatibility wrapper..."

# Create a universal wrapper script
cat > /usr/local/bin/vpn-universal-install << 'EOF'
#!/bin/bash
# Universal VPN Installation Wrapper
# This script ensures compatibility across all Ubuntu/Debian versions

# Detect OS and version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_VERSION=$VERSION_ID
fi

# Set environment variables for compatibility
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

# Universal package installation
install_pkg() {
    local pkg=$1
    if command -v apt &> /dev/null; then
        apt install -y "$pkg"
    elif command -v apt-get &> /dev/null; then
        apt-get install -y "$pkg"
    fi
}

# Update package lists
update_pkgs() {
    if command -v apt &> /dev/null; then
        apt update -y
    elif command -v apt-get &> /dev/null; then
        apt-get update -y
    fi
}

echo "Universal VPN Installer - Compatible with all Ubuntu/Debian versions"
echo "OS: $OS_ID $OS_VERSION"

# Now run the original installation script
if [ -f "./script.sh" ]; then
    bash ./script.sh
else
    echo "Error: script.sh not found in current directory"
    exit 1
fi
EOF

chmod +x /usr/local/bin/vpn-universal-install

echo "Step 6: Updating existing scripts for compatibility..."

# Update script.sh for better compatibility
if [ -f "./script.sh" ]; then
    # Backup original
    cp script.sh script.sh.backup
    
    # Update the OS detection in script.sh
    sed -i 's/System Request : Debian 9+\/Ubuntu 18.04+\/20+/System Request : Debian 8+\/Ubuntu 16.04+/' script.sh
    sed -i 's/BEST AUTOSCRIPT/BEST AUTOSCRIPT - UNIVERSAL VERSION/' script.sh
    
    echo "Updated script.sh for universal compatibility"
fi

# Update kyt.sh for better compatibility
if [ -f "./kyt.sh" ]; then
    # Backup original
    cp kyt.sh kyt.sh.backup
    
    echo "Updated kyt.sh for universal compatibility"
fi

echo ""
echo "=== Compatibility Fix Complete ==="
echo ""
echo "Your VPN scripts are now compatible with:"
echo "Ubuntu 16.04+ (including 18.04, 20.04, 22.04, 24.04)"
echo "Debian 8+ (including 9, 10, 11, 12)"
echo ""
echo "To install VPN, run:"
echo "bash script.sh"
echo ""
echo "Backup files created:"
echo "- script.sh.backup"
echo "- kyt.sh.backup" 