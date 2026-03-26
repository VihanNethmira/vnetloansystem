#!/bin/bash

echo "------------------------------------------------"
echo "   VNET SHOP - UNIVERSAL DEPLOYMENT TOOL"
echo "------------------------------------------------"
echo "1. Install/Deploy New System"
echo "2. Uninstall/Remove Existing System"
read -p "Choose an option (1 or 2): " MAIN_OPT

# --- UNINSTALL LOGIC ---
if [ "$MAIN_OPT" == "2" ]; then
    read -p "Enter the Domain to remove: " UN_DOMAIN
    read -p "Enter the Port to close: " UN_PORT
    read -p "Enter the Project Folder name in /root/: " UN_FOLDER

    echo "Uninstalling $UN_DOMAIN..."
    sudo systemctl stop vnet_app
    sudo systemctl disable vnet_app
    sudo rm /etc/systemd/system/vnet_app.service
    sudo systemctl daemon-reload

    sudo rm /etc/nginx/sites-enabled/vnet_app
    sudo rm /etc/nginx/sites-available/vnet_app
    sudo systemctl restart nginx

    sudo ufw deny $UN_PORT/tcp
    sudo ufw reload

    read -p "Do you want to delete the project folder /root/$UN_FOLDER? (y/n): " DEL_FOLD
    if [ "$DEL_FOLD" == "y" ]; then
        sudo rm -rf /root/$UN_FOLDER
    fi

    echo "SUCCESS: $UN_DOMAIN has been removed."
    exit 1
fi

# --- INSTALL LOGIC ---
if [ "$MAIN_OPT" == "1" ]; then
    read -p "Enter your domain (e.g., vnet.vpnpremium.shop): " DOMAIN
    read -p "Enter your desired Nginx port (e.g., 9000): " PORT
    read -p "Enter your project folder name in /root/ (e.g., Loans): " FOLDER

    mkdir -p /root/$FOLDER
    cd /root/$FOLDER

    sudo apt update && sudo apt install -y python3-pip python3-venv nginx certbot python3-certbot-nginx

    python3 -m venv venv
    source venv/bin/activate
    pip install flask gunicorn

    # Create Service
    cat <<EOF | sudo tee /etc/systemd/system/vnet_app.service
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
    cat <<EOF | sudo tee /etc/nginx/sites-available/vnet_app
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

    sudo ln -s /etc/nginx/sites-available/vnet_app /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    chmod +x /root
    sudo systemctl daemon-reload
    sudo systemctl enable vnet_app
    sudo systemctl enable nginx
    sudo ufw allow $PORT/tcp
    sudo ufw reload

    echo "Running SSL Configuration..."
    sudo systemctl stop nginx
    sudo certbot certonly --standalone -d $DOMAIN
    sudo systemctl start nginx
    sudo systemctl restart vnet_app

    echo "DEPLOYMENT FINISHED! Access at https://$DOMAIN:$PORT"
fi