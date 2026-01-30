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

if [ "$EUID" -eq 0 ]; then
    USE_SUDO=""
else
    USE_SUDO="sudo"
fi

echo "======================================"
echo " VPS BACKUP SYSTEM SETUP"
echo "======================================"

# Set timezone to East African Time (EAT - UTC+3)
log_info "Setting timezone to Africa/Nairobi (East African Time)..."
${USE_SUDO} timedatectl set-timezone Africa/Nairobi

# Verify timezone
CURRENT_TZ=$(timedatectl | grep "Time zone" | awk '{print $3}')
log_info "Current timezone: $CURRENT_TZ"

# Create backup directories
log_info "Creating backup directory structure..."
BACKUP_ROOT="/var/backups/vps"
${USE_SUDO} mkdir -p ${BACKUP_ROOT}/{databases,files,configs,logs}
${USE_SUDO} mkdir -p ${BACKUP_ROOT}/databases/{postgresql,mysql,redis}
${USE_SUDO} mkdir -p ${BACKUP_ROOT}/files/{projects,nginx,docker}
${USE_SUDO} mkdir -p ${BACKUP_ROOT}/configs

# Set proper permissions
${USE_SUDO} chmod 700 ${BACKUP_ROOT}

log_info "Creating comprehensive backup script..."
${USE_SUDO} tee /usr/local/bin/vps-backup.sh > /dev/null <<'BACKUPSCRIPT'
#!/bin/bash

set -e

BACKUP_ROOT="/var/backups/vps"
DATE=$(date +%Y%m%d_%H%M%S)
DAY_OF_WEEK=$(date +%A)
RETENTION_DAYS=7
WEEKLY_RETENTION=4
MONTHLY_RETENTION=3

LOG_FILE="${BACKUP_ROOT}/logs/backup_${DATE}.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "======================================"
log "Starting VPS Backup - $DATE"
log "======================================"

# PostgreSQL Backup
log "Backing up PostgreSQL databases..."
if systemctl is-active --quiet postgresql; then
    PGBACKUP_DIR="${BACKUP_ROOT}/databases/postgresql"
    
    # Backup all databases
    sudo -u postgres pg_dumpall > "${PGBACKUP_DIR}/all_databases_${DATE}.sql"
    
    # Backup individual databases
    sudo -u postgres psql -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;" | while read -r dbname; do
        if [ ! -z "$dbname" ]; then
            dbname=$(echo $dbname | xargs)
            sudo -u postgres pg_dump "$dbname" > "${PGBACKUP_DIR}/${dbname}_${DATE}.sql"
            log "Backed up PostgreSQL database: $dbname"
        fi
    done
    
    # Compress PostgreSQL backups
    gzip "${PGBACKUP_DIR}"/*_${DATE}.sql
    log "PostgreSQL backup completed and compressed"
else
    log "PostgreSQL is not running, skipping..."
fi

# MySQL Backup
log "Backing up MySQL databases..."
if systemctl is-active --quiet mysql; then
    MYSQLBACKUP_DIR="${BACKUP_ROOT}/databases/mysql"
    
    # Backup all databases
    mysqldump --all-databases --single-transaction --quick --lock-tables=false > "${MYSQLBACKUP_DIR}/all_databases_${DATE}.sql"
    
    # Backup individual databases
    mysql -e "SHOW DATABASES;" | grep -Ev "Database|information_schema|performance_schema|mysql|sys" | while read -r dbname; do
        mysqldump --single-transaction --quick --lock-tables=false "$dbname" > "${MYSQLBACKUP_DIR}/${dbname}_${DATE}.sql"
        log "Backed up MySQL database: $dbname"
    done
    
    # Compress MySQL backups
    gzip "${MYSQLBACKUP_DIR}"/*_${DATE}.sql
    log "MySQL backup completed and compressed"
else
    log "MySQL is not running, skipping..."
fi

# Redis Backup
log "Backing up Redis..."
if systemctl is-active --quiet redis-server; then
    REDISBACKUP_DIR="${BACKUP_ROOT}/databases/redis"
    
    # Trigger Redis save
    redis-cli BGSAVE
    sleep 2
    
    # Copy RDB file
    if [ -f /var/lib/redis/dump.rdb ]; then
        cp /var/lib/redis/dump.rdb "${REDISBACKUP_DIR}/dump_${DATE}.rdb"
        gzip "${REDISBACKUP_DIR}/dump_${DATE}.rdb"
        log "Redis backup completed"
    else
        log "Redis dump file not found"
    fi
else
    log "Redis is not running, skipping..."
fi

# Backup important files
log "Backing up important files and directories..."

# Backup /root or /home projects
if [ -d /root/projects ]; then
    tar -czf "${BACKUP_ROOT}/files/projects/root_projects_${DATE}.tar.gz" -C /root projects 2>/dev/null || log "Warning: Some files in /root/projects were inaccessible"
    log "Backed up /root/projects"
fi

# Backup Nginx configurations
if [ -d /etc/nginx ]; then
    tar -czf "${BACKUP_ROOT}/files/nginx/nginx_config_${DATE}.tar.gz" /etc/nginx 2>/dev/null
    log "Backed up Nginx configurations"
fi

# Backup Docker volumes
if [ -d /var/lib/docker/volumes ]; then
    tar -czf "${BACKUP_ROOT}/files/docker/docker_volumes_${DATE}.tar.gz" /var/lib/docker/volumes 2>/dev/null || log "Warning: Some Docker volumes were inaccessible"
    log "Backed up Docker volumes"
fi

# Backup system configurations
log "Backing up system configurations..."
CONFIG_BACKUP_DIR="${BACKUP_ROOT}/configs"

# Important config files
tar -czf "${CONFIG_BACKUP_DIR}/system_configs_${DATE}.tar.gz" \
    /etc/hosts \
    /etc/hostname \
    /etc/fstab \
    /etc/crontab \
    /etc/environment \
    /etc/nginx \
    /etc/redis \
    /etc/mysql \
    /etc/postgresql \
    /etc/systemd/system/*.service \
    2>/dev/null || log "Warning: Some config files were inaccessible"

log "System configurations backed up"

# Backup crontabs
crontab -l > "${CONFIG_BACKUP_DIR}/root_crontab_${DATE}.txt" 2>/dev/null || log "No root crontab found"

# Create backup manifest
log "Creating backup manifest..."
MANIFEST_FILE="${BACKUP_ROOT}/backup_manifest_${DATE}.txt"
cat > "$MANIFEST_FILE" <<EOF
VPS Backup Manifest
Date: $(date)
Hostname: $(hostname)
Timezone: $(timedatectl | grep "Time zone" | awk '{print $3}')

=== Backup Contents ===
EOF

find ${BACKUP_ROOT} -name "*${DATE}*" -type f -exec ls -lh {} \; >> "$MANIFEST_FILE"

# Calculate total backup size
TOTAL_SIZE=$(du -sh ${BACKUP_ROOT} | awk '{print $1}')
echo "" >> "$MANIFEST_FILE"
echo "Total Backup Size: $TOTAL_SIZE" >> "$MANIFEST_FILE"
log "Backup manifest created"

# Cleanup old backups
log "Cleaning up old backups..."

# Daily backups - keep for $RETENTION_DAYS days
find ${BACKUP_ROOT}/databases -name "*.sql.gz" -mtime +${RETENTION_DAYS} -delete
find ${BACKUP_ROOT}/databases -name "*.rdb.gz" -mtime +${RETENTION_DAYS} -delete
find ${BACKUP_ROOT}/files -name "*.tar.gz" -mtime +${RETENTION_DAYS} -delete
find ${BACKUP_ROOT}/configs -name "*.tar.gz" -mtime +${RETENTION_DAYS} -delete
find ${BACKUP_ROOT}/logs -name "*.log" -mtime +30 -delete

log "Old backups cleaned up (kept last ${RETENTION_DAYS} days)"

# Weekly backups (every Sunday)
if [ "$DAY_OF_WEEK" = "Sunday" ]; then
    log "Creating weekly backup archive..."
    WEEKLY_BACKUP_DIR="${BACKUP_ROOT}/weekly"
    mkdir -p "${WEEKLY_BACKUP_DIR}"
    
    tar -czf "${WEEKLY_BACKUP_DIR}/weekly_backup_${DATE}.tar.gz" \
        ${BACKUP_ROOT}/databases \
        ${BACKUP_ROOT}/files \
        ${BACKUP_ROOT}/configs
    
    # Keep only last 4 weekly backups
    find ${WEEKLY_BACKUP_DIR} -name "*.tar.gz" -mtime +$((WEEKLY_RETENTION * 7)) -delete
    log "Weekly backup created"
fi

# Monthly backups (1st of month)
if [ $(date +%d) = "01" ]; then
    log "Creating monthly backup archive..."
    MONTHLY_BACKUP_DIR="${BACKUP_ROOT}/monthly"
    mkdir -p "${MONTHLY_BACKUP_DIR}"
    
    tar -czf "${MONTHLY_BACKUP_DIR}/monthly_backup_${DATE}.tar.gz" \
        ${BACKUP_ROOT}/databases \
        ${BACKUP_ROOT}/files \
        ${BACKUP_ROOT}/configs
    
    # Keep only last 3 monthly backups
    find ${MONTHLY_BACKUP_DIR} -name "*.tar.gz" -mtime +$((MONTHLY_RETENTION * 30)) -delete
    log "Monthly backup created"
fi

# Final summary
log "======================================"
log "Backup completed successfully!"
log "Backup location: ${BACKUP_ROOT}"
log "Total size: $TOTAL_SIZE"
log "======================================"

# Send notification (optional - uncomment if you want email notifications)
# echo "VPS Backup completed successfully on $(hostname) at $(date)" | mail -s "Backup Success - $(hostname)" your-email@example.com

exit 0
BACKUPSCRIPT

${USE_SUDO} chmod +x /usr/local/bin/vps-backup.sh

log_info "Creating backup verification script..."
${USE_SUDO} tee /usr/local/bin/verify-backups.sh > /dev/null <<'VERIFYSCRIPT'
#!/bin/bash

BACKUP_ROOT="/var/backups/vps"

echo "======================================"
echo "VPS Backup Verification"
echo "======================================"
echo ""

echo "Timezone: $(timedatectl | grep "Time zone" | awk '{print $3}')"
echo "Current time: $(date)"
echo ""

echo "=== Recent Backups ==="
echo ""

echo "PostgreSQL backups (last 5):"
ls -lht ${BACKUP_ROOT}/databases/postgresql/*.gz 2>/dev/null | head -5 || echo "No PostgreSQL backups found"
echo ""

echo "MySQL backups (last 5):"
ls -lht ${BACKUP_ROOT}/databases/mysql/*.gz 2>/dev/null | head -5 || echo "No MySQL backups found"
echo ""

echo "Redis backups (last 5):"
ls -lht ${BACKUP_ROOT}/databases/redis/*.gz 2>/dev/null | head -5 || echo "No Redis backups found"
echo ""

echo "File backups (last 5):"
ls -lht ${BACKUP_ROOT}/files/*/*.tar.gz 2>/dev/null | head -5 || echo "No file backups found"
echo ""

echo "=== Disk Usage ==="
du -sh ${BACKUP_ROOT}/*
echo ""

echo "=== Last Backup Log ==="
LAST_LOG=$(ls -t ${BACKUP_ROOT}/logs/*.log 2>/dev/null | head -1)
if [ -f "$LAST_LOG" ]; then
    echo "Log file: $LAST_LOG"
    echo ""
    tail -20 "$LAST_LOG"
else
    echo "No log files found"
fi
VERIFYSCRIPT

${USE_SUDO} chmod +x /usr/local/bin/verify-backups.sh

log_info "Creating restore script template..."
${USE_SUDO} tee /usr/local/bin/restore-backup.sh > /dev/null <<'RESTORESCRIPT'
#!/bin/bash

BACKUP_ROOT="/var/backups/vps"

echo "======================================"
echo "VPS Backup Restore Script"
echo "======================================"
echo ""
echo "WARNING: This will restore backups and may overwrite existing data!"
echo ""

if [ -z "$1" ]; then
    echo "Usage: $0 <backup_date>"
    echo ""
    echo "Available backup dates:"
    ls ${BACKUP_ROOT}/databases/postgresql/*.sql.gz 2>/dev/null | sed 's/.*_\([0-9]*_[0-9]*\).*/\1/' | sort -u
    exit 1
fi

BACKUP_DATE=$1

echo "Restoring backups from: $BACKUP_DATE"
echo ""

# Restore PostgreSQL
echo "=== PostgreSQL Restore ==="
PGBACKUP="${BACKUP_ROOT}/databases/postgresql/all_databases_${BACKUP_DATE}.sql.gz"
if [ -f "$PGBACKUP" ]; then
    read -p "Restore PostgreSQL? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        gunzip -c "$PGBACKUP" | sudo -u postgres psql
        echo "PostgreSQL restored"
    fi
else
    echo "PostgreSQL backup not found: $PGBACKUP"
fi
echo ""

# Restore MySQL
echo "=== MySQL Restore ==="
MYSQLBACKUP="${BACKUP_ROOT}/databases/mysql/all_databases_${BACKUP_DATE}.sql.gz"
if [ -f "$MYSQLBACKUP" ]; then
    read -p "Restore MySQL? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        gunzip -c "$MYSQLBACKUP" | mysql
        echo "MySQL restored"
    fi
else
    echo "MySQL backup not found: $MYSQLBACKUP"
fi
echo ""

# Restore Redis
echo "=== Redis Restore ==="
REDISBACKUP="${BACKUP_ROOT}/databases/redis/dump_${BACKUP_DATE}.rdb.gz"
if [ -f "$REDISBACKUP" ]; then
    read -p "Restore Redis? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        systemctl stop redis-server
        gunzip -c "$REDISBACKUP" > /var/lib/redis/dump.rdb
        chown redis:redis /var/lib/redis/dump.rdb
        systemctl start redis-server
        echo "Redis restored"
    fi
else
    echo "Redis backup not found: $REDISBACKUP"
fi

echo ""
echo "Restore process completed!"
RESTORESCRIPT

${USE_SUDO} chmod +x /usr/local/bin/restore-backup.sh

log_info "Setting up automatic backup schedule..."

# Remove any existing backup cron jobs
${USE_SUDO} crontab -l 2>/dev/null | grep -v "vps-backup.sh" | ${USE_SUDO} crontab - 2>/dev/null || true

# Add new cron job - runs every night at 2:00 AM EAT
(${USE_SUDO} crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/vps-backup.sh >> /var/backups/vps/logs/cron.log 2>&1") | ${USE_SUDO} crontab -

log_info "Cron job scheduled: Daily backup at 2:00 AM EAT"

log_info "Creating backup monitoring script..."
${USE_SUDO} tee /usr/local/bin/backup-status.sh > /dev/null <<'STATUSSCRIPT'
#!/bin/bash

BACKUP_ROOT="/var/backups/vps"

echo "======================================"
echo "VPS Backup Status"
echo "======================================"
echo ""

echo "Current time (EAT): $(date)"
echo ""

# Check if backup ran today
TODAY=$(date +%Y%m%d)
LAST_BACKUP=$(ls -t ${BACKUP_ROOT}/logs/backup_*.log 2>/dev/null | head -1)

if [ -f "$LAST_BACKUP" ]; then
    BACKUP_DATE=$(echo "$LAST_BACKUP" | grep -o '[0-9]\{8\}_[0-9]\{6\}' | cut -d_ -f1)
    
    if [ "$BACKUP_DATE" = "$TODAY" ]; then
        echo "✓ Backup completed today"
    else
        echo "✗ No backup today (last backup: $BACKUP_DATE)"
    fi
    
    echo ""
    echo "Last backup details:"
    tail -5 "$LAST_BACKUP"
else
    echo "✗ No backups found"
fi

echo ""
echo "Next scheduled backup: 2:00 AM EAT"
echo ""

# Show cron job
echo "Cron schedule:"
sudo crontab -l | grep vps-backup
STATUSSCRIPT

${USE_SUDO} chmod +x /usr/local/bin/backup-status.sh

log_info "Testing backup system..."
log_warn "Running initial backup (this may take a few minutes)..."
${USE_SUDO} /usr/local/bin/vps-backup.sh

echo ""
echo "======================================"
echo " BACKUP SYSTEM SETUP COMPLETE!"
echo "======================================"
echo ""
log_info "Timezone: Africa/Nairobi (EAT - UTC+3)"
log_info "Backup schedule: Every night at 2:00 AM EAT"
log_info "Backup location: /var/backups/vps"
log_info "Retention: 7 days (daily), 4 weeks (weekly), 3 months (monthly)"
echo ""
echo "Available commands:"
echo "  verify-backups.sh      - Check recent backups"
echo "  backup-status.sh       - Check backup system status"
echo "  restore-backup.sh      - Restore from backup"
echo "  vps-backup.sh          - Run backup manually"
echo ""
log_info "Verifying backup system..."
${USE_SUDO} /usr/local/bin/verify-backups.sh
