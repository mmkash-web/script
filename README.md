# Universal VPN Auto-Installer

## Installation

```bash
apt install -y curl wget && apt update -y && apt upgrade -y && wget -q https://raw.githubusercontent.com/mmkash-web/script/main/script.sh && sed -i 's/\r$//' script.sh && chmod +x script.sh && ./script.sh
```

---

## Supported Operating Systems

### Ubuntu
- Ubuntu 16.04 LTS (Xenial)
- Ubuntu 18.04 LTS (Bionic)
- Ubuntu 20.04 LTS (Focal)
- Ubuntu 22.04 LTS (Jammy)
- Ubuntu 24.04 LTS (Noble)
- All future Ubuntu versions

### Debian
- Debian 8 (Jessie)
- Debian 9 (Stretch)
- Debian 10 (Buster)
- Debian 11 (Bullseye)
- Debian 12 (Bookworm)
- All future Debian versions

---

## System Requirements

- Architecture: x86_64 (64-bit)
- RAM: 512MB minimum (1GB recommended)
- Storage: 10GB free space
- Internet connection

---

## Troubleshooting

### HAProxy fails to start
```bash
systemctl stop haproxy
sed -i '/^[[:space:]]*bind-process[[:space:]]/d' /etc/haproxy/haproxy.cfg
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl restart haproxy
systemctl status haproxy --no-pager
```

### Check service logs
```bash
journalctl -u haproxy --no-pager -n 50
journalctl -u xray --no-pager -n 50
```

### Reload all services
```bash
systemctl daemon-reload
systemctl restart haproxy nginx xray
```

---

## Support

- Telegram: https://t.me/emmkash
- WhatsApp: wa.me/+254112735877
- Email: EMMKASH20@GMAIL.COM

---

Made by EMMKASH Technologies Kenya
