#!/bin/bash

# Clear screen for a clean look
clear
echo "------------------------------------------------"
echo "   VNET SHOP - UNIVERSAL DEPLOYMENT TOOL"
echo "   Domain: vnet.vpnpremium.shop | Port: 9000"
echo "------------------------------------------------"
echo "1. Install / Deploy System"
echo "2. Uninstall / Remove System"
echo "3. Check System Status"
echo "4. Exit"
read -p "Choose an option (1-4): " MAIN_OPT

# --- SETTINGS ---
# We use a static service name to keep it simple for the script to manage
SERVICE_NAME="vnet_ledger"

# --- 1. INSTALL LOGIC ---
if [ "$MAIN_OPT" == "1" ]; then
    read -p "Enter your domain (e.g., vnet.vpnpremium.shop): " DOMAIN
    read -p "Enter your desired Nginx port (e.g., 9000): " PORT
    read -p "Enter your project folder name in /root/ (e.g., Loans): " FOLDER

    echo "Updating system and installing dependencies..."
    sudo apt update && sudo apt install -y python3-pip python3-venv nginx certbot python3-certbot-nginx

    mkdir -p /root/$FOLDER
    cd /root/$FOLDER

    echo "Setting up Python Virtual Environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install flask gunicorn

    # Create the Systemd Service
    cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Gunicorn instance for $FOLDER
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

    # Enable everything
    sudo ln -s /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    chmod +x /root
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl enable nginx
    sudo ufw allow $PORT/tcp
    sudo ufw reload

    echo "Stopping Nginx to generate SSL..."
    sudo systemctl stop nginx
    sudo certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email
    sudo systemctl start nginx
    
    # Final check: If app.py exists, start it. If not, warn user.
    if [ -f "/root/$FOLDER/app.py" ]; then
        sudo systemctl restart $SERVICE_NAME
        echo "SUCCESS: System is live at https://$DOMAIN:$PORT"
    else
        echo "WARNING: System installed, but app.py was not found in /root/$FOLDER."
        echo "Please upload your code, then run: sudo systemctl restart $SERVICE_NAME"
    fi

# --- 2. UNINSTALL LOGIC ---
elif [ "$MAIN_OPT" == "2" ]; then
    read -p "Enter the Port to close: " UN_PORT
    read -p "Enter the Folder name to check for deletion: " UN_FOLDER

    echo "Cleaning up system files..."
    sudo systemctl stop $SERVICE_NAME
    sudo systemctl disable $SERVICE_NAME
    sudo rm -f /etc/systemd/system/$SERVICE_NAME.service
    sudo systemctl daemon-reload

    sudo rm -f /etc/nginx/sites-enabled/$SERVICE_NAME
    sudo rm -f /etc/nginx/sites-available/$SERVICE_NAME
    sudo systemctl restart nginx

    sudo ufw deny $UN_PORT/tcp
    sudo ufw reload

    read -p "Delete all code and databases in /root/$UN_FOLDER? (y/n): " DEL_FOLD
    if [ "$DEL_FOLD" == "y" ]; then
        sudo rm -rf /root/$UN_FOLDER
    fi
    echo "Uninstall complete."

# --- 3. STATUS CHECK ---
elif [ "$MAIN_OPT" == "3" ]; then
    echo "Checking service status..."
    sudo systemctl status $SERVICE_NAME --no-pager
    echo "------------------------------------------------"
    echo "Checking Nginx status..."
    sudo systemctl status nginx --no-pager
    echo "------------------------------------------------"
    echo "Active Ports:"
    sudo ufw status | grep ALLOW

else
    echo "Exiting..."
    exit 1
fi
