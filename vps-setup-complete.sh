#!/usr/bin/env bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

NODE_VERSION="24"
GO_VERSION="1.22.0"
TIMEZONE="UTC"

if [ "$EUID" -eq 0 ]; then
    USE_SUDO=""
else
    USE_SUDO="sudo"
fi

echo "======================================"
echo " VPS FULL DEV SETUP (Ubuntu)"
echo "======================================"

log_info "Setting timezone to $TIMEZONE..."
${USE_SUDO} timedatectl set-timezone $TIMEZONE

log_info "Updating system packages..."
${USE_SUDO} apt update && ${USE_SUDO} apt upgrade -y

log_info "Installing core tools and utilities..."
${USE_SUDO} apt install -y \
    build-essential \
    ca-certificates \
    software-properties-common \
    apt-transport-https \
    curl \
    wget \
    git \
    unzip \
    htop \
    ripgrep \
    bat \
    fzf \
    vim \
    gnupg \
    lsb-release \
    certbot \
    python3-certbot-nginx

log_info "Configuring UFW firewall..."
${USE_SUDO} apt install -y ufw
${USE_SUDO} ufw allow OpenSSH
${USE_SUDO} ufw allow 80
${USE_SUDO} ufw allow 443
${USE_SUDO} ufw allow 3000:3010/tcp
${USE_SUDO} ufw allow 5432/tcp
${USE_SUDO} ufw allow 3306/tcp
${USE_SUDO} ufw allow 6379/tcp
${USE_SUDO} ufw default deny incoming
${USE_SUDO} ufw default allow outgoing
${USE_SUDO} ufw --force enable

log_info "Installing and configuring Fail2ban..."
${USE_SUDO} apt install -y fail2ban
${USE_SUDO} systemctl enable fail2ban
${USE_SUDO} systemctl start fail2ban

log_info "Installing Nginx..."
${USE_SUDO} apt install -y nginx
${USE_SUDO} systemctl enable nginx
${USE_SUDO} systemctl start nginx

${USE_SUDO} mkdir -p /etc/nginx/sites-available
${USE_SUDO} mkdir -p /etc/nginx/sites-enabled
${USE_SUDO} mkdir -p /var/www/html

log_info "Installing Redis..."
${USE_SUDO} apt install -y redis-server
${USE_SUDO} systemctl enable redis-server
${USE_SUDO} systemctl start redis-server

${USE_SUDO} sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
${USE_SUDO} systemctl restart redis-server

log_info "Installing Python and tools..."
${USE_SUDO} apt install -y python3 python3-pip python3-venv python3-dev python3-full pipx

pip3 install --break-system-packages --ignore-installed pipenv poetry virtualenv

log_info "Installing NVM..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
fi

echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc

log_info "Installing Node.js 24 (latest) via NVM..."
nvm install 24
nvm use 24
nvm alias default 24

log_info "Verifying Node.js installation..."
node --version
npm --version

log_info "Installing npm, yarn, pnpm..."
npm install -g yarn pnpm

log_info "Installing PM2..."
npm install -g pm2

if [ "$EUID" -eq 0 ]; then
    pm2 startup systemd -u root --hp /root
else
    pm2 startup systemd -u $USER --hp $HOME
    ${USE_SUDO} env PATH=$PATH:/usr/bin pm2 startup systemd -u $USER --hp $HOME
fi

pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:retain 7

log_info "Installing Bun..."
curl -fsSL https://bun.sh/install | bash

if [ "$EUID" -eq 0 ]; then
    export BUN_INSTALL="/root/.bun"
else
    export BUN_INSTALL="$HOME/.bun"
fi

export PATH="$BUN_INSTALL/bin:$PATH"
echo "export BUN_INSTALL=\"$BUN_INSTALL\"" >> ~/.bashrc
echo "export PATH=\"\$BUN_INSTALL/bin:\$PATH\"" >> ~/.bashrc

log_info "Installing Docker..."
curl -fsSL https://get.docker.com | ${USE_SUDO} sh
${USE_SUDO} systemctl enable docker
${USE_SUDO} systemctl start docker

if [ "$EUID" -ne 0 ]; then
    ${USE_SUDO} usermod -aG docker $USER
fi

log_info "Installing Docker Compose..."
${USE_SUDO} curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
${USE_SUDO} chmod +x /usr/local/bin/docker-compose

log_info "Installing PostgreSQL..."
${USE_SUDO} apt install -y postgresql postgresql-contrib postgresql-client
${USE_SUDO} systemctl enable postgresql
${USE_SUDO} systemctl start postgresql

log_info "Installing MySQL..."
${USE_SUDO} apt install -y mysql-server mysql-client
${USE_SUDO} systemctl enable mysql
${USE_SUDO} systemctl start mysql

log_info "Installing Go ${GO_VERSION}..."
cd /tmp
wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
${USE_SUDO} rm -rf /usr/local/go
${USE_SUDO} tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
rm go${GO_VERSION}.linux-amd64.tar.gz

echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.bashrc
echo "export GOPATH=\$HOME/go" >> ~/.bashrc
echo "export PATH=\$PATH:\$GOPATH/bin" >> ~/.bashrc
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

log_info "Installing Zsh and Oh My Zsh..."
${USE_SUDO} apt install -y zsh

RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true

if [ "$EUID" -eq 0 ]; then
    ${USE_SUDO} chsh -s $(which zsh) root || true
else
    ${USE_SUDO} chsh -s $(which zsh) $USER || true
fi

log_info "Installing frontend development dependencies..."
${USE_SUDO} apt install -y \
    libcairo2-dev \
    libpango1.0-dev \
    libjpeg-dev \
    libgif-dev \
    librsvg2-dev

log_info "Installing Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi
echo "source \"\$HOME/.cargo/env\"" >> ~/.bashrc

log_info "Installing global Node.js packages..."
npm install -g \
    typescript \
    ts-node \
    nodemon \
    eslint \
    prettier \
    create-react-app \
    vite \
    next

log_info "Installing monitoring tools..."
${USE_SUDO} apt install -y \
    nethogs \
    iotop \
    git-flow

log_info "Creating project directories..."
mkdir -p ~/projects/frontend
mkdir -p ~/projects/backend
mkdir -p ~/projects/docker
mkdir -p ~/logs
mkdir -p ~/backups

log_info "Creating Nginx configuration templates..."

${USE_SUDO} tee /etc/nginx/sites-available/react-template > /dev/null <<'REACTEOF'
server {
    listen 80;
    server_name example.com;
    
    root /var/www/example.com;
    index index.html;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/rss+xml font/truetype font/opentype application/vnd.ms-fontobject image/svg+xml;
}
REACTEOF

${USE_SUDO} tee /etc/nginx/sites-available/nodejs-api-template > /dev/null <<'APIEOF'
server {
    listen 80;
    server_name api.example.com;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
APIEOF

log_info "Creating deployment script template..."
tee ~/deploy-template.sh > /dev/null <<'DEPLOYEOF'
#!/bin/bash

APP_NAME="myapp"
APP_DIR="~/projects/backend/$APP_NAME"
PORT=3000

cd $APP_DIR
git pull origin main
npm install
pm2 restart $APP_NAME || pm2 start npm --name $APP_NAME -- start
pm2 save
DEPLOYEOF

chmod +x ~/deploy-template.sh

log_info "Creating database backup script..."
tee ~/backup-databases.sh > /dev/null <<'BACKUPEOF'
#!/bin/bash

BACKUP_DIR="$HOME/backups"
DATE=$(date +%Y%m%d_%H%M%S)

sudo -u postgres pg_dumpall > "$BACKUP_DIR/postgres_backup_$DATE.sql"

mysqldump --all-databases -u root > "$BACKUP_DIR/mysql_backup_$DATE.sql"

find $BACKUP_DIR -name "*.sql" -mtime +7 -delete

echo "Backup completed: $DATE"
BACKUPEOF

chmod +x ~/backup-databases.sh

(crontab -l 2>/dev/null; echo "0 2 * * * $HOME/backup-databases.sh >> $HOME/logs/backup.log 2>&1") | crontab -

log_info "Creating system info script..."
tee ~/system-info.sh > /dev/null <<'INFOEOF'
#!/bin/bash

echo "=== System Information ==="
echo "Node.js: $(node --version)"
echo "npm: $(npm --version)"
echo "yarn: $(yarn --version)"
echo "pnpm: $(pnpm --version)"
echo "Bun: $(bun --version)"
echo "Python: $(python3 --version)"
echo "Go: $(go version)"
echo "Rust: $(rustc --version)"
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker-compose --version)"
echo "PostgreSQL: $(psql --version)"
echo "MySQL: $(mysql --version)"
echo "Redis: $(redis-cli --version)"
echo "Nginx: $(nginx -v 2>&1)"
echo "PM2: $(pm2 --version)"
echo "Zsh: $(zsh --version)"
INFOEOF

chmod +x ~/system-info.sh

log_info "Applying security configurations..."

echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" | ${USE_SUDO} tee -a /etc/fstab

if [ ! -f /swapfile ]; then
    log_info "Creating swap file..."
    ${USE_SUDO} fallocate -l 2G /swapfile
    ${USE_SUDO} chmod 600 /swapfile
    ${USE_SUDO} mkswap /swapfile
    ${USE_SUDO} swapon /swapfile
    echo "/swapfile none swap sw 0 0" | ${USE_SUDO} tee -a /etc/fstab
fi

log_info "Optimizing system limits..."
${USE_SUDO} tee -a /etc/security/limits.conf > /dev/null <<LIMITSEOF
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
LIMITSEOF

log_info "Creating quick reference guide..."
tee ~/SETUP_GUIDE.md > /dev/null <<'GUIDEEOF'
# VPS Setup Complete

## Installed Tools

### Languages & Runtimes
- Node.js 24 (via NVM) + npm + yarn + pnpm
- Bun
- Python 3 + pip
- Go 1.22.0
- Rust

### Databases
- PostgreSQL + client
- MySQL + client
- Redis

### Web Server & Reverse Proxy
- Nginx

### Process Management
- PM2 (with log rotation)
- Docker + Docker Compose

### Shell
- Zsh + Oh My Zsh

### Development Tools
- Git + Git Flow
- NVM
- TypeScript, ESLint, Prettier
- Vite, Create React App, Next.js
- ripgrep, bat, fzf

### Monitoring
- htop, nethogs, iotop

## Quick Commands

### NVM (Node Version Manager)
nvm install 22          # Install Node.js 22
nvm use 22              # Switch to Node.js 22
nvm alias default 22    # Set default version
nvm list                # List installed versions
nvm current             # Show current version

### PM2
pm2 start app.js --name myapp
pm2 list
pm2 logs myapp
pm2 restart myapp
pm2 stop myapp
pm2 save

### Nginx
sudo nginx -t
sudo systemctl reload nginx
sudo systemctl restart nginx

### Docker
docker ps
docker-compose up -d
docker-compose down
docker logs -f container_name

### Database Access
sudo -u postgres psql
sudo mysql
redis-cli

### SSL Certificate
sudo certbot --nginx -d yourdomain.com

## Useful Scripts

- ~/system-info.sh - Display installed versions
- ~/backup-databases.sh - Backup all databases
- ~/deploy-template.sh - Template for app deployment

## Next Steps

1. Log out and back in for all changes
2. Secure MySQL: sudo mysql_secure_installation
3. Create PostgreSQL users and databases
4. Configure domain in Nginx
5. Set up SSL certificate
GUIDEEOF

log_info "Cleaning up..."
${USE_SUDO} apt autoremove -y
${USE_SUDO} apt autoclean -y

echo ""
echo "======================================"
echo " SETUP COMPLETE!"
echo "======================================"
echo ""
echo "Installed:"
echo "- Nginx"
echo "- Redis"
echo "- Python 3"
echo "- Node.js 24 (via NVM) / npm / yarn / pnpm"
echo "- Bun"
echo "- PM2 (with log rotation)"
echo "- Docker + Docker Compose"
echo "- PostgreSQL + client"
echo "- MySQL + client"
echo "- Go ${GO_VERSION}"
echo "- Rust"
echo "- Zsh + Oh My Zsh"
echo "- NVM"
echo "- ripgrep, bat, fzf"
echo ""
log_warn "IMPORTANT: Log out and log back in for all changes to take effect"
echo ""
log_info "Run ~/system-info.sh to verify installations"
log_info "Read ~/SETUP_GUIDE.md for next steps"
echo ""

if [ -f ~/.bashrc ]; then
    source ~/.bashrc 2>/dev/null || true
fi

if [ -x ~/system-info.sh ]; then
    ~/system-info.sh
fi
