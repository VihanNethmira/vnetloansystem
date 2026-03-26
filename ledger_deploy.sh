#!/bin/bash
clear
echo "------------------------------------------------"
echo "   VNET SHOP - UNIVERSAL DEPLOYMENT TOOL"
echo "------------------------------------------------"
echo "1. Full Install / Update (Includes GitHub Pull)"
echo "2. Uninstall / Remove System"
echo "3. Check System Status"
echo "4. Exit"
read -p "Choose an option (1-4): " MAIN_OPT

SERVICE_NAME="vnet_ledger"

if [ "$MAIN_OPT" == "1" ]; then
    read -p "Enter Domain (vnet.vpnpremium.shop): " DOMAIN
    read -p "Enter Port (9000): " PORT
    read -p "GitHub Repo URL (to pull app.py): " REPO_URL
    FOLDER="Loans"

    sudo apt update && sudo apt install -y python3-pip python3-venv nginx certbot python3-certbot-nginx git

    mkdir -p /root/$FOLDER
    cd /root/$FOLDER

    # --- GitHub Integration ---
    if [ ! -d ".git" ]; then
        git clone $REPO_URL .
    else
        git pull origin main
    fi

    python3 -m venv venv
    source venv/bin/activate
    pip install flask gunicorn

    # Create Service
    cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Gunicorn instance for $FOLDER
After=network.target
[Service]
User=root
WorkingDirectory=/root/$FOLDER
ExecStart=/root/$FOLDER/venv/bin/gunicorn --bind 127.0.0.1:8888 app:app
Restart=always
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
    }
}
EOF

    sudo ln -s /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    chmod +x /root
    
    # SSL Generation (Handles stop/start automatically)
    sudo systemctl stop nginx
    sudo certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email
    sudo systemctl start nginx

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl restart $SERVICE_NAME
    echo "SUCCESS: https://$DOMAIN:$PORT is live!"

elif [ "$MAIN_OPT" == "2" ]; then
    # ... (Uninstall logic from previous version)
    echo "Uninstalling..."
    sudo systemctl stop $SERVICE_NAME
    sudo rm -f /etc/systemd/system/$SERVICE_NAME.service
    sudo rm -f /etc/nginx/sites-enabled/$SERVICE_NAME
    echo "Done."
elif [ "$MAIN_OPT" == "3" ]; then
    sudo systemctl status $SERVICE_NAME --no-pager
fi
