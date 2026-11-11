#!/bin/bash
# Universal Update Script for VPN Installation
# Compatible with all Ubuntu and Debian versions

# Detect OS and set package manager
if command -v apt &> /dev/null; then
    PKG_MGR="apt"
elif command -v apt-get &> /dev/null; then
    PKG_MGR="apt-get"
else
    echo "Error: No supported package manager found"
    exit 1
fi

# Universal package installation function
install_pkg() {
    local pkg=$1
    if [ "$PKG_MGR" = "apt" ]; then
        apt install -y "$pkg"
    elif [ "$PKG_MGR" = "apt-get" ]; then
        apt-get install -y "$pkg"
    fi
}

# Update package lists
update_pkgs() {
    if [ "$PKG_MGR" = "apt" ]; then
        apt update -y
    elif [ "$PKG_MGR" = "apt-get" ]; then
        apt-get update -y
    fi
}

# Get date from server
dateFromServer=$(curl -v --insecure --silent https://google.com/ 2>&1 | grep Date | sed -e 's/< Date: //')
biji=`date +"%Y-%m-%d" -d "$dateFromServer"`

# Color definitions
red() { echo -e "\\033[32;1m${*}\\033[0m"; }

clear

# Progress bar function
fun_bar() {
    CMD[0]="$1"
    CMD[1]="$2"
    (
        [[ -e $HOME/fim ]] && rm $HOME/fim
        ${CMD[0]} -y >/dev/null 2>&1
        ${CMD[1]} -y >/dev/null 2>&1
        touch $HOME/fim
    ) >/dev/null 2>&1 &
    tput civis
    echo -ne "  \033[0;33mPlease Wait Loading \033[1;37m- \033[0;33m["
    while true; do
        for ((i = 0; i < 18; i++)); do
            echo -ne "\033[0;32m#"
            sleep 0.1s
        done
        [[ -e $HOME/fim ]] && rm $HOME/fim && break
        echo -e "\033[0;33m]"
        sleep 1s
        tput cuu1
        tput dl1
        echo -ne "  \033[0;33mPlease Wait Loading \033[1;37m- \033[0;33m["
    done
    echo -e "\033[0;33m]\033[1;37m -\033[1;32m OK !\033[1;37m"
    tput cnorm
}

# Update function
res1() {
    # Install required packages for update
    install_pkg "wget"
    install_pkg "unzip"
    
    # Download and install menu
    wget -q https://raw.githubusercontent.com/mmkash-web/script/main/ubuntu/menu.zip
    unzip -q menu.zip
    chmod +x menu/*
    mv menu/* /usr/local/sbin
    rm -rf menu menu.zip

    # ── Update Xray config.json ───────────────────────────────────
    # Pulls the latest config from the repo. The placeholder UUID
    # (1d1c1d94-...) stays in place; existing user accounts stored
    # in the file are preserved because we only replace the file if
    # it currently has no active user entries (lines starting with
    # #& / ### / #! / #ss#). If users are present we skip the
    # config overwrite to avoid wiping accounts.
    has_users=$(grep -cE "^(#& |### |#! |#ss# )" /etc/xray/config.json 2>/dev/null || echo 0)
    if [ "$has_users" -eq 0 ]; then
        echo "Updating Xray config.json..."
        cp /etc/xray/config.json /etc/xray/config.json.bak 2>/dev/null || true
        wget -q -O /etc/xray/config.json \
            "https://raw.githubusercontent.com/mmkash-web/script/main/ubuntu/config.json"
        domain=$(cat /etc/xray/domain 2>/dev/null || echo "")
        systemctl restart xray 2>/dev/null || true
        echo "Xray config updated and restarted."
    else
        echo "Active Xray users found — skipping config.json overwrite to preserve accounts."
    fi

    # ── Update HAProxy config ─────────────────────────────────────
    # Pulls the latest haproxy.cfg template and applies the domain
    # substitution, then runs configure_haproxy-style validation.
    if [ -f /etc/haproxy/haproxy.cfg ]; then
        echo "Updating HAProxy config..."
        cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
        domain=$(cat /etc/xray/domain 2>/dev/null || echo "")
        wget -q -O /etc/haproxy/haproxy.cfg \
            "https://raw.githubusercontent.com/mmkash-web/script/main/ubuntu/haproxy.cfg"
        if [ -n "$domain" ]; then
            sed -i "s/xxx/${domain}/g" /etc/haproxy/haproxy.cfg
        fi
        # Strip any bind-process / pidfile directives (fatal on HAProxy 2.1+)
        sed -i '/^[[:space:]]*bind-process[[:space:]]/d' /etc/haproxy/haproxy.cfg
        sed -i '/^[[:space:]]*pidfile[[:space:]]/d'       /etc/haproxy/haproxy.cfg
        # Validate before restarting
        if haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
            systemctl reset-failed haproxy 2>/dev/null || true
            systemctl restart haproxy 2>/dev/null || true
            echo "HAProxy config updated and restarted."
        else
            echo "HAProxy config validation failed — restoring backup."
            cp /etc/haproxy/haproxy.cfg.bak /etc/haproxy/haproxy.cfg
        fi
    fi

    rm -rf update.sh
}

# Install netfilter-persistent if not present
if ! command -v netfilter-persistent &> /dev/null; then
    echo "Installing netfilter-persistent..."
    install_pkg "netfilter-persistent"
fi

clear

echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e " \e[1;97;101m          UPDATED SCRIPT POWERED BY EMMKASH TECH     \e[0m"
echo -e " \e[1;97;101m          UNIVERSAL VERSION - ALL UBUNTU/DEBIAN      \e[0m"
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e ""
echo -e "  \033[1;91m update script service\033[1;37m"
fun_bar 'res1'
echo -e "\033[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e ""
read -n 1 -s -r -p "Press [ Enter ] to back on menu"
menu

###########- COLOR CODE -##############
