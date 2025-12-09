#!/bin/bash
# Ubuntu 22+ Compatibility Fix for VPN Script
# Fixes HAProxy, Nginx, and Dropbear issues

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}=== Ubuntu 22+ Compatibility Fix ===${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Detect OS version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_VERSION=$VERSION_ID
    echo -e "Detected: ${GREEN}$PRETTY_NAME${NC}"
else
    echo -e "${RED}Cannot detect OS${NC}"
    exit 1
fi

# Function to check if service is running
check_service() {
    local service=$1
    if systemctl is-active --quiet $service 2>/dev/null; then
        echo -e "${GREEN}✓ $service is running${NC}"
        return 0
    else
        echo -e "${RED}✗ $service is NOT running${NC}"
        return 1
    fi
}

echo ""
echo "Step 1: Checking current service status..."
check_service nginx
check_service haproxy
check_service dropbear

echo ""
echo "Step 2: Fixing HAProxy for Ubuntu 22+..."

# Stop haproxy first
systemctl stop haproxy 2>/dev/null

# Remove old haproxy and install compatible version
apt remove --purge haproxy -y 2>/dev/null
apt autoremove -y 2>/dev/null

# For Ubuntu 22+, install from default repos (HAProxy 2.4+)
apt update -y
apt install -y haproxy

# Create HAProxy directory if not exists
mkdir -p /run/haproxy
chown haproxy:haproxy /run/haproxy

# Fix HAProxy config for newer versions
if [ -f /etc/haproxy/haproxy.cfg ]; then
    # Backup original
    cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
    
    # Remove deprecated bind-process directive
    sed -i 's/bind-process 1 2//g' /etc/haproxy/haproxy.cfg
    sed -i 's/bind-process 1//g' /etc/haproxy/haproxy.cfg
    
    # Fix TFO issues - remove tfo if causing problems
    # sed -i 's/ tfo//g' /etc/haproxy/haproxy.cfg
    
    echo -e "${GREEN}HAProxy config updated${NC}"
fi

# Check if certificate exists
if [ ! -f /etc/haproxy/hap.pem ]; then
    echo "Creating HAProxy certificate..."
    if [ -f /etc/xray/xray.crt ] && [ -f /etc/xray/xray.key ]; then
        cat /etc/xray/xray.crt /etc/xray/xray.key > /etc/haproxy/hap.pem
        chmod 600 /etc/haproxy/hap.pem
    else
        echo -e "${RED}Warning: SSL certificates not found${NC}"
    fi
fi

# Enable and start haproxy
systemctl daemon-reload
systemctl enable haproxy
systemctl start haproxy

echo ""
echo "Step 3: Fixing Nginx..."

# Stop nginx first
systemctl stop nginx 2>/dev/null

# Reinstall nginx
apt install -y nginx

# Check nginx config syntax
nginx -t 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}Nginx config has errors, attempting fix...${NC}"
    
    # Check if xray.conf exists and has issues
    if [ -f /etc/nginx/conf.d/xray.conf ]; then
        # Backup
        cp /etc/nginx/conf.d/xray.conf /etc/nginx/conf.d/xray.conf.bak
        
        # Common fixes for nginx config on Ubuntu 22+
        # Remove deprecated TLSv1 and TLSv1.1
        sed -i 's/TLSv1 TLSv1.1 //g' /etc/nginx/conf.d/xray.conf
        sed -i 's/TLSv1.1 //g' /etc/nginx/conf.d/xray.conf
        
        # Fix http2 directive for newer nginx (1.25.1+)
        # The old way: listen 81 ssl http2
        # The new way: listen 81 ssl; http2 on;
        sed -i 's/listen \([0-9]*\) ssl http2/listen \1 ssl/g' /etc/nginx/conf.d/xray.conf
        sed -i 's/listen \([0-9]*\) http2 proxy_protocol/listen \1 proxy_protocol/g' /etc/nginx/conf.d/xray.conf
    fi
    
    # Test again
    nginx -t
fi

# Check if SSL certificates exist, create temporary ones if not
if [ ! -f /etc/xray/xray.crt ] || [ ! -f /etc/xray/xray.key ]; then
    echo -e "${RED}SSL certificates not found, creating temporary self-signed certs...${NC}"
    mkdir -p /etc/xray
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/xray/xray.key -out /etc/xray/xray.crt \
        -subj "/C=US/ST=State/L=City/O=Org/CN=localhost" 2>/dev/null
    chmod 644 /etc/xray/xray.crt
    chmod 600 /etc/xray/xray.key
    echo -e "${GREEN}Temporary SSL certificates created${NC}"
    echo "Run 'fixcert' from menu later to get proper Let's Encrypt certificates"
    
    # Also create haproxy cert
    cat /etc/xray/xray.crt /etc/xray/xray.key > /etc/haproxy/hap.pem
    chmod 600 /etc/haproxy/hap.pem
fi

# Enable and start nginx
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx

echo ""
echo "Step 4: Fixing Dropbear for Ubuntu 22+..."

# Stop dropbear
systemctl stop dropbear 2>/dev/null
/etc/init.d/dropbear stop 2>/dev/null

# Reinstall dropbear
apt install -y dropbear

# Ubuntu 22+ uses different config location
# Check if using systemd or init.d
if [ -f /etc/default/dropbear ]; then
    # Traditional config exists, update it
    cat > /etc/default/dropbear << 'EOF'
# Dropbear config for Ubuntu 22+
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER="/etc/kyt.txt"
DROPBEAR_RECEIVE_WINDOW=65536
EOF
    echo -e "${GREEN}Dropbear config updated${NC}"
fi

# Create systemd override for dropbear if needed
mkdir -p /etc/systemd/system/dropbear.service.d/
cat > /etc/systemd/system/dropbear.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/sbin/dropbear -F -p 143 -p 109 -b /etc/kyt.txt
EOF

# Create banner file if not exists
if [ ! -f /etc/kyt.txt ]; then
    echo "Welcome to VPN Server" > /etc/kyt.txt
fi

# Generate host keys if missing
if [ ! -f /etc/dropbear/dropbear_rsa_host_key ]; then
    mkdir -p /etc/dropbear
    dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
fi
if [ ! -f /etc/dropbear/dropbear_ecdsa_host_key ]; then
    dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key
fi

# For Ubuntu 22+, dropbear uses init.d not native systemd
# Avoid systemctl enable/restart which can hang
/etc/init.d/dropbear stop 2>/dev/null
sleep 1
/etc/init.d/dropbear start 2>/dev/null

# If init.d fails, start manually
if ! pgrep -x "dropbear" > /dev/null; then
    echo "Starting dropbear manually..."
    /usr/sbin/dropbear -p 143 -p 109 -b /etc/kyt.txt 2>/dev/null &
fi

echo ""
echo "Step 5: Restarting all services..."

systemctl restart nginx 2>/dev/null
systemctl restart haproxy 2>/dev/null
systemctl restart xray 2>/dev/null
systemctl restart ws 2>/dev/null

# Dropbear via init.d to avoid hang
/etc/init.d/dropbear restart 2>/dev/null

# Wait for services to start
sleep 3

echo ""
echo "=== Final Service Status ==="
check_service nginx
check_service haproxy
check_service dropbear
check_service xray
check_service ssh

echo ""
echo -e "${GREEN}=== Fix Complete ===${NC}"
echo ""
echo "If services are still not running, check logs with:"
echo "  journalctl -xe -u haproxy"
echo "  journalctl -xe -u nginx"
echo "  journalctl -xe -u dropbear"
echo ""
echo "Run 'menu' to check status in the VPN menu"
