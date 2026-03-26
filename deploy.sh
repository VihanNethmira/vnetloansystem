#!/bin/bash
clear
echo "------------------------------------------------"
echo "   VNET SHOP - UNIVERSAL DEPLOYMENT TOOL"
echo "------------------------------------------------"
echo "1. Install / Update System"
echo "2. Uninstall System"
echo "3. Exit"
read -p "Choose an option: " OPT

SERVICE_NAME="vnet_ledger"
FOLDER="Loans"

if [ "$OPT" == "1" ]; then
    read -p "Enter Domain (vnet.vpnpremium.shop): " DOMAIN
    read -p "Enter Port (9000): " PORT

    # 1. Install Ubuntu Dependencies
    sudo apt update && sudo apt install -y python3-pip python3-venv nginx certbot python3-certbot-nginx git

    # 2. Setup Folder & Pull Code
    mkdir -p /root/$FOLDER
    cd /root/$FOLDER
    if [ ! -d ".git" ]; then
        git clone https://github.com/VihanNethmira/vnetloansystem.git .
    else
        git pull origin main
    fi

    # 3. Python Setup
    python3 -m venv venv
    source venv/bin/activate
    pip install flask gunicorn

    # 4. Create Service & Nginx Config
    cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Gunicorn instance for VNET Ledger
After=network.target
[Service]
User=root
WorkingDirectory=/root/$FOLDER
ExecStart=/root/$FOLDER/venv/bin/gunicorn --bind 127.0.0.1:8888 app:app
Restart=always
EOF

    cat <<EOF | sudo tee /etc/nginx/sites-available/$SERVICE_NAME
server {
    listen $PORT ssl;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:8888;
        proxy_set_header Host \$host;
    }
}
EOF

    # 5. SSL & Firewalls
    sudo ln -s /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default
    chmod +x /root
    sudo systemctl stop nginx
    sudo certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email
    sudo systemctl start nginx
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl restart $SERVICE_NAME
    sudo ufw allow $PORT/tcp
    
    echo "SUCCESS: Ledger live at https://$DOMAIN:$PORT"
fi
