# Automated-VPS-development-environment-setup-script

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
