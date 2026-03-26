#!/bin/bash
# VNET SHOP Universal Deployer

read -p "Enter Domain (vnet.vpnpremium.shop): " DOMAIN
read -p "Enter Port (9000): " PORT

# 1. System Requirements
sudo apt update && sudo apt install -y python3-pip python3-venv nginx certbot python3-certbot-nginx git

# 2. Project Setup
mkdir -p /root/Loans
cd /root/Loans

# 3. Pull Code from GitHub
if [ ! -d ".git" ]; then
    git clone https://github.com/VihanNethmira/vnetloansystem.git .
else
    git pull origin main
fi

# 4. Virtual Environment
python3 -m venv venv
source venv/bin/activate
pip install flask gunicorn

# 5. Background Service Configuration
cat <<EOF | sudo tee /etc/systemd/system/vnet_ledger.service
[Unit]
Description=Gunicorn instance for VNET Ledger
After=network.target

[Service]
User=root
WorkingDirectory=/root/Loans
ExecStart=/root/Loans/venv/bin/gunicorn --bind 127.0.0.1:8888 app:app
Restart=always
EOF

# 6. SSL & Nginx (Auto-stop/start for Certbot)
sudo systemctl stop nginx
sudo certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email
sudo systemctl start nginx

# 7. Final Firewalls & Permissions
chmod +x /root
sudo systemctl daemon-reload
sudo systemctl enable vnet_ledger
sudo systemctl restart vnet_ledger
sudo ufw allow $PORT/tcp
sudo ufw reload

echo "SUCCESS! Visit https://$DOMAIN:$PORT"
