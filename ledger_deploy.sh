#!/bin/bash

# --- CONFIGURATION ---
SERVICE_NAME="vnet_ledger"
FOLDER="Loans"
APP_PORT="8888"

# Clear screen for a clean interface
clear
echo "------------------------------------------------"
echo "   VNET SHOP - UNIVERSAL DEPLOYMENT TOOL"
echo "   OS: Ubuntu | Port: 9000 (Customizable)"
echo "------------------------------------------------"
echo "1. Full Install / Update (GitHub Pull)"
echo "2. Uninstall / Remove System"
echo "3. Check Service Status"
echo "4. Exit"
read -p "Choose an option (1-4): " MAIN_OPT

# --- 1. INSTALL / UPDATE LOGIC ---
if [ "$MAIN_OPT" == "1" ]; then
    read -p "Enter Domain (e.g., vnet.vpnpremium.shop): " DOMAIN
    read -p "Enter Nginx Port (e.g., 9000): " PORT
    read -p "GitHub Repo URL: " REPO_URL

    echo "Installing system dependencies..."
    sudo apt update && sudo apt install -y python3-pip python3-venv nginx certbot python3-certbot-nginx git

    mkdir -p /root/$FOLDER
    cd /root/$FOLDER

    # Clone or Pull latest code from GitHub
    if [ ! -d ".git" ]; then
        echo "Cloning repository..."
        git clone $REPO_URL .
    else
        echo "Pulling latest changes..."
        git pull origin main
    fi

    # Setup Virtual Environment
    echo "Setting up Python environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install flask gunicorn

    # Create Systemd Service (Autostart)
    cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Gunicorn instance for VNET Ledger
After=network.target

[Service]
User=root
WorkingDirectory=/root/$FOLDER
ExecStart=/root/$FOLDER/venv/bin/gunicorn --bind 127.0.0.1:$APP_PORT app:app
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
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Apply Nginx settings
    sudo ln -s /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    
    # Fix Ubuntu Root Permissions
    chmod +x /root
    
    # SSL Generation
    echo "Configuring SSL..."
    sudo systemctl stop nginx
    sudo certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email
    sudo systemctl start nginx

    # Finalize Service
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl restart $SERVICE_NAME
    
    # Firewall
    sudo ufw allow $PORT/tcp
    sudo ufw reload

    echo "------------------------------------------------"
    echo "SUCCESS: Ledger is live at https://$DOMAIN:$PORT"
    echo "------------------------------------------------"

# --- 2. UNINSTALL LOGIC ---
elif [ "$MAIN_OPT" == "2" ]; then
    read -p "Enter the Nginx Port you want to close: " UN_PORT
    echo "Removing VNET Ledger system files..."
    
    sudo systemctl stop $SERVICE_NAME
    sudo systemctl disable $SERVICE_NAME
    sudo rm -f /etc/systemd/system/$SERVICE_NAME.service
    sudo systemctl daemon-reload

    sudo rm -f /etc/nginx/sites-enabled/$SERVICE_NAME
    sudo rm -f /etc/nginx/sites-available/$SERVICE_NAME
    sudo systemctl restart nginx

    sudo ufw deny $UN_PORT/tcp
    sudo ufw reload

    read -p "Do you want to delete the code and databases in /root/$FOLDER? (y/n): " DEL_FOLD
    if [ "$DEL_FOLD" == "y" ]; then
        sudo rm -rf /root/$FOLDER
        echo "Folder deleted."
    fi
    echo "Uninstall complete."

# --- 3. STATUS LOGIC ---
elif [ "$MAIN_OPT" == "3" ]; then
    echo "Service Status:"
    sudo systemctl status $SERVICE_NAME --no-pager
    echo "------------------------------------------------"
    echo "Nginx Status:"
    sudo systemctl status nginx --no-pager
    echo "------------------------------------------------"
    echo "Firewall Allowed Ports:"
    sudo ufw status | grep ALLOW

else
    echo "Exiting."
    exit 1
fi