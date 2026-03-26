#!/bin/bash

# Clear screen for a clean interface
clear
echo "------------------------------------------------"
echo "   VNET SHOP - UNIVERSAL DEPLOYMENT TOOL"
echo "   OS: Ubuntu | Root Directory: /root/Loans"
echo "------------------------------------------------"
echo "1. Install / Update System (Pull from GitHub)"
echo "2. Uninstall / Remove System"
echo "3. Check System Status"
echo "4. Exit"
read -p "Choose an option (1-4): " MAIN_OPT

# Settings
SERVICE_NAME="vnet_ledger"

if [ "$MAIN_OPT" == "1" ]; then
    read -p "Enter Domain (e.g., vnet.vpnpremium.shop): " DOMAIN
    read -p "Enter Port (e.g., 9000): " PORT
    read -p "GitHub Repo URL: " REPO_URL
    FOLDER="Loans"

    echo "Installing dependencies..."
    sudo apt update && sudo apt install -y python3-pip python3-venv nginx certbot python3-certbot-nginx git

    mkdir -p /root/$FOLDER
    cd /root/$FOLDER

    # Clone or Pull latest code
    if [ ! -d ".git" ]; then
        git clone $REPO_URL .
    else
        git pull origin main
    fi

    # Setup Environment
    python3 -m venv venv
    source venv/bin/activate
    pip install flask gunicorn

    # Create Service File
    cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Gunicorn instance for VNET Ledger
After=network.target

[Service]
User=root
WorkingDirectory=/root/$FOLDER
ExecStart=/root/$FOLDER/venv/bin/gunicorn --bind 127.0.0.1:8888 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Create Nginx Config
    cat <<EOF | sudo tee /etc/nginx/sites-available/$SERVICE_NAME
server {
    listen $PORT ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8888;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Finalize permissions and SSL
    sudo ln -s /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    chmod +x /root
    
    echo "Stopping Nginx to verify SSL..."
    sudo systemctl stop nginx
    sudo certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email
    sudo systemctl start nginx

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl restart $SERVICE_NAME
    sudo ufw allow $PORT/tcp
    sudo ufw reload

    echo "SUCCESS: Ledger is live at https://$DOMAIN:$PORT"

elif [ "$MAIN_OPT" == "2" ]; then
    read -p "Enter Port to close: " UN_PORT
    sudo systemctl stop $SERVICE_NAME
    sudo systemctl disable $SERVICE_NAME
    sudo rm -f /etc/systemd/system/$SERVICE_NAME.service
    sudo rm -f /etc/nginx/sites-enabled/$SERVICE_NAME
    sudo rm -f /etc/nginx/sites-available/$SERVICE_NAME
    sudo ufw deny $UN_PORT/tcp
    sudo systemctl restart nginx
    echo "Uninstall Complete."

elif [ "$MAIN_OPT" == "3" ]; then
    sudo systemctl status $SERVICE_NAME --no-pager
    echo "------------------------------------------------"
    sudo ufw status | grep ALLOW
fi
