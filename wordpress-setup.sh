#!/bin/bash

# WordPress + Nginx Setup Script for Ubuntu 22.04/24.04
# Author: ToolConverts.com Setup
# Usage: sudo bash wordpress-setup.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration Variables
DOMAIN="blog.toolconverts.com"
WP_ADMIN_USER="admin"
WP_ADMIN_EMAIL="admin@toolconverts.com"
MYSQL_ROOT_PASSWORD=""
WP_DB_NAME="toolconverts"
WP_DB_USER="wp_toolconverts"
WP_DB_PASSWORD="XMu1ApNXImwVaCX"

# Functions
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

generate_password() {
    openssl rand -base64 12
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run this script as root or with sudo"
    exit 1
fi

print_status "Starting WordPress + Nginx setup on Ubuntu..."

# Update system
print_status "Updating system packages..."
apt update && apt upgrade -y

# Install essential packages
print_status "Installing essential packages..."
apt install -y curl wget unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release

# Install Nginx
print_status "Installing Nginx..."
apt install -y nginx

# Install MySQL
print_status "Installing MySQL Server..."
apt install -y mysql-server

# Install PHP 8.2 and extensions
print_status "Installing PHP 8.2 and required extensions..."
add-apt-repository ppa:ondrej/php -y
apt update
apt install -y php8.2 php8.2-fpm php8.2-mysql php8.2-curl php8.2-gd php8.2-intl \
    php8.2-mbstring php8.2-soap php8.2-xml php8.2-xmlrpc php8.2-zip php8.2-cli \
    php8.2-common php8.2-opcache php8.2-readline php8.2-imagick

# Generate passwords if not set
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    MYSQL_ROOT_PASSWORD=$(generate_password)
    print_warning "Generated MySQL root password: $MYSQL_ROOT_PASSWORD"
fi

if [ -z "$WP_DB_PASSWORD" ]; then
    WP_DB_PASSWORD=$(generate_password)
    print_warning "Generated WordPress DB password: $WP_DB_PASSWORD"
fi

# Secure MySQL installation
print_status "Securing MySQL installation..."
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DELETE FROM mysql.user WHERE User='';"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DROP DATABASE IF EXISTS test;"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"

# Create WordPress database and user
print_status "Creating WordPress database and user..."
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $WP_DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE USER '$WP_DB_USER'@'localhost' IDENTIFIED BY '$WP_DB_PASSWORD';"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL ON $WP_DB_NAME.* TO '$WP_DB_USER'@'localhost';"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"

# Download and setup WordPress
print_status "Downloading and setting up WordPress..."
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar xzf latest.tar.gz

# Copy WordPress files
cp -a /tmp/wordpress/. /var/www/blog/
rm -rf /var/www/blog/index.nginx-debian.html

# Set permissions
print_status "Setting file permissions..."
chown -R www-data:www-data /var/www/blog/
find /var/www/blog/ -type d -exec chmod 750 {} \;
find /var/www/blog/ -type f -exec chmod 640 {} \;

# Configure WordPress
print_status "Configuring WordPress..."
cd /var/www/blog
cp wp-config-sample.php wp-config.php

# WordPress security keys
SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)

# Update wp-config.php
sed -i "s/database_name_here/$WP_DB_NAME/" wp-config.php
sed -i "s/username_here/$WP_DB_USER/" wp-config.php
sed -i "s/password_here/$WP_DB_PASSWORD/" wp-config.php

# Replace salt section
sed -i '/AUTH_KEY/,/NONCE_SALT/c\
'"$SALT"'' wp-config.php

# Add additional security configurations
cat >> wp-config.php << 'EOF'

// Additional Security Settings
define('DISALLOW_FILE_EDIT', true);
define('FORCE_SSL_ADMIN', true);
define('WP_AUTO_UPDATE_CORE', true);

// Memory and upload limits
define('WP_MEMORY_LIMIT', '512M');
define('WP_MAX_MEMORY_LIMIT', '512M');

// Database settings
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);

EOF

# Configure PHP-FPM
print_status "Configuring PHP-FPM..."
cp /etc/php/8.2/fpm/php.ini /etc/php/8.2/fpm/php.ini.backup

# PHP optimizations
sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.2/fpm/php.ini
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 100M/' /etc/php/8.2/fpm/php.ini
sed -i 's/post_max_size = .*/post_max_size = 100M/' /etc/php/8.2/fpm/php.ini
sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/8.2/fpm/php.ini
sed -i 's/max_input_time = .*/max_input_time = 300/' /etc/php/8.2/fpm/php.ini

# Configure Nginx
print_status "Configuring Nginx..."

# Backup default config
mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup

# Create WordPress Nginx config
cat > /etc/nginx/sites-available/default << EOF
# WordPress Nginx Configuration for $DOMAIN
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;
    root /var/www/blog;
    index index.php index.html index.htm;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    # Handle WordPress permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # Handle PHP files
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        
        # Security
        fastcgi_hide_header X-Powered-By;
        fastcgi_read_timeout 300;
    }

    # WordPress security
    location ~* /(?:uploads|files)/.*\.php$ {
        deny all;
    }

    location ~* \.(log|binary|pem|enc|crt|conf|cnf|sql|sh|key)$ {
        deny all;
    }

    location ~* ^.+\.(ogg|ogv|svg|svgz|eot|otf|woff|mp4|ttf|rss|atom|jpg|jpeg|gif|png|ico|zip|tgz|gz|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf)$ {
        access_log off; 
        log_not_found off; 
        expires max;
        add_header Cache-Control "public, immutable";
    }

    # Deny access to sensitive files
    location ~* \.(htaccess|htpasswd|ini|log|sh|sql|conf)$ {
        deny all;
    }

    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
    }

    # WordPress admin security
    location ~* wp-admin/includes {
        deny all;
    }

    location ~* wp-includes/[^/]+\.php$ {
        deny all;
    }

    location ~* wp-config\.php {
        deny all;
    }

    # Hide sensitive directories
    location ~ /\.ht {
        deny all;
    }

    location ~ /\.git {
        deny all;
    }
}
EOF

# Test Nginx configuration
print_status "Testing Nginx configuration..."
nginx -t

if [ $? -ne 0 ]; then
    print_error "Nginx configuration test failed!"
    exit 1
fi

# Install WP-CLI
print_status "Installing WP-CLI..."
curl -O https://raw.githubusercontent.com/wp-cli/wp-cli/v2.8.1/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Make WP-CLI available for www-data
print_status "Configuring WP-CLI for www-data user..."
sudo -u www-data wp --info --path=/var/www/blog > /dev/null 2>&1 || true

# Install WordPress via WP-CLI
print_status "Installing WordPress via WP-CLI..."
cd /var/www/blog

# Generate admin password
WP_ADMIN_PASSWORD=$(generate_password)

# WordPress installation
sudo -u www-data wp core install \
    --url="http://$DOMAIN" \
    --title="ToolConverts - Công cụ chuyển đổi file online" \
    --admin_user="$WP_ADMIN_USER" \
    --admin_password="$WP_ADMIN_PASSWORD" \
    --admin_email="$WP_ADMIN_EMAIL"

# Install essential plugins
print_status "Installing essential WordPress plugins..."
sudo -u www-data wp plugin install --activate \
    yoast-seo \
    w3-total-cache \
    wordfence \
    updraftplus \
    contact-form-7

# Install and activate a clean theme
sudo -u www-data wp theme install --activate astra

# Basic WordPress optimizations
print_status "Applying WordPress optimizations..."

# Disable comments globally
sudo -u www-data wp option update default_comment_status closed
sudo -u www-data wp option update default_ping_status closed

# Set permalink structure
sudo -u www-data wp rewrite structure '/%postname%/' --hard

# Configure basic settings
sudo -u www-data wp option update blogname "ToolConverts"
sudo -u www-data wp option update blogdescription "Công cụ chuyển đổi file & tiện ích online miễn phí"
sudo -u www-data wp option update timezone_string "Asia/Ho_Chi_Minh"
sudo -u www-data wp option update date_format "d/m/Y"
sudo -u www-data wp option update time_format "H:i"

# Configure cache (if W3 Total Cache is installed)
print_status "Configuring basic caching..."
sudo -u www-data wp w3-total-cache option set pgcache.enabled true 2>/dev/null || true
sudo -u www-data wp w3-total-cache option set minify.enabled true 2>/dev/null || true

# Install SSL with Let's Encrypt
print_status "Installing Certbot for SSL..."
apt install -y snapd
snap install core; snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot

# Update Nginx config for HTTPS
cat > /etc/nginx/sites-available/default << EOF
# WordPress Nginx Configuration with SSL for $DOMAIN
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    root /var/www/blog;
    index index.php index.html index.htm;

    # SSL configuration (will be updated by certbot)
    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/javascript
        application/xml+rss
        application/json
        image/svg+xml;

    # WordPress permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # PHP handling
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        
        fastcgi_hide_header X-Powered-By;
        fastcgi_read_timeout 300;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }

    # Static files caching
    location ~* \.(css|gif|ico|jpeg|jpg|js|png|svg|webp|woff|woff2|ttf|eot|mp4|webm)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Security rules for WordPress
    location ~* /(?:uploads|files)/.*\.php$ {
        deny all;
    }

    location ~* \.(log|binary|pem|enc|crt|conf|cnf|sql|sh|key)$ {
        deny all;
    }

    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
    }

    location ~* wp-admin/includes {
        deny all;
    }

    location ~* wp-includes/[^/]+\.php$ {
        deny all;
    }

    location ~* wp-config\.php {
        deny all;
    }

    location ~ /\.ht {
        deny all;
    }

    location ~ /\.git {
        deny all;
    }

    # WordPress admin area rate limiting
    location ^~ /wp-admin/ {
        limit_req zone=admin burst=5 nodelay;
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location = /wp-login.php {
        limit_req zone=login burst=2 nodelay;
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
    }
}
EOF

# Add rate limiting to main nginx.conf
sed -i '/http {/a\\n    # Rate limiting zones\n    limit_req_zone $binary_remote_addr zone=admin:10m rate=1r/s;\n    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/m;' /etc/nginx/nginx.conf

# Create self-signed SSL certificate (temporary)
print_status "Creating temporary SSL certificate..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nginx-selfsigned.key \
    -out /etc/ssl/certs/nginx-selfsigned.crt \
    -subj "/C=VN/ST=HoChiMinh/L=HoChiMinh/O=ToolConverts/CN=$DOMAIN"

# Configure PHP-FPM pool
print_status "Optimizing PHP-FPM..."
cp /etc/php/8.2/fpm/pool.d/www.conf /etc/php/8.2/fpm/pool.d/www.conf.backup

cat > /etc/php/8.2/fpm/pool.d/www.conf << 'EOF'
[www]
user = www-data
group = www-data
listen = /var/run/php/php8.2-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.process_idle_timeout = 10s
pm.max_requests = 1000
chdir = /
security.limit_extensions = .php
EOF

# Restart services
print_status "Restarting services..."
systemctl restart php8.2-fpm
systemctl restart nginx
systemctl restart mysql

# Enable services to start on boot
systemctl enable nginx
systemctl enable php8.2-fpm
systemctl enable mysql

# Setup firewall
print_status "Configuring UFW firewall..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 'Nginx Full'
ufw allow mysql

# Create backup script
print_status "Creating backup script..."
cat > /root/wordpress-backup.sh << 'EOF'
#!/bin/bash
# WordPress Backup Script

BACKUP_DIR="/root/backups"
DATE=$(date +%Y%m%d_%H%M%S)
WP_PATH="/var/www/blog"

mkdir -p $BACKUP_DIR

# Database backup
mysqldump -u root -p$MYSQL_ROOT_PASSWORD $WP_DB_NAME > $BACKUP_DIR/db_backup_$DATE.sql

# Files backup
tar -czf $BACKUP_DIR/files_backup_$DATE.tar.gz -C $WP_PATH .

# Keep only last 7 backups
find $BACKUP_DIR -type f -mtime +7 -delete

echo "Backup completed: $DATE"
EOF

chmod +x /root/wordpress-backup.sh

# Add backup to crontab (daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * /root/wordpress-backup.sh") | crontab -

# Create WordPress CLI aliases
cat >> /root/.bashrc << 'EOF'

# WordPress aliases
alias wp='sudo -u www-data wp --path=/var/www/blog'
alias wp-update='sudo -u www-data wp --path=/var/www/blog core update && sudo -u www-data wp --path=/var/www/blog plugin update --all'
alias wp-backup='/root/wordpress-backup.sh'
alias nginx-reload='nginx -t && systemctl reload nginx'
EOF

# Set up log rotation
print_status "Configuring log rotation..."
cat > /etc/logrotate.d/wordpress << 'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    notifempty
    create 0644 www-data www-data
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
            run-parts /etc/logrotate.d/httpd-prerotate; \
        fi \
    endscript
    postrotate
        systemctl reload nginx
    endscript
}

/var/log/php8.2-fpm.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    sharedscripts
    postrotate
        systemctl reload php8.2-fpm
    endscript
}
EOF

# Security hardening script
print_status "Creating security hardening script..."
cat > /root/wordpress-security.sh << 'EOF'
#!/bin/bash
# WordPress Security Hardening

# Update all packages
apt update && apt upgrade -y

# WordPress updates
sudo -u www-data wp --path=/var/www/blog core update
sudo -u www-data wp --path=/var/www/blog plugin update --all
sudo -u www-data wp --path=/var/www/blog theme update --all

# File permissions check
find /var/www/blog/ -type d -exec chmod 750 {} \;
find /var/www/blog/ -type f -exec chmod 640 {} \;
chmod 600 /var/www/blog/wp-config.php

# Check for malware (basic)
find /var/www/blog -name "*.php" -exec grep -l "eval\|base64_decode\|gzinflate" {} \;

echo "Security check completed: $(date)"
EOF

chmod +x /root/wordpress-security.sh

# Add security check to crontab (weekly)
(crontab -l 2>/dev/null; echo "0 3 * * 0 /root/wordpress-security.sh") | crontab -

# Final status check
print_status "Performing final status check..."
systemctl is-active --quiet nginx && print_success "Nginx is running" || print_error "Nginx is not running"
systemctl is-active --quiet php8.2-fpm && print_success "PHP-FPM is running" || print_error "PHP-FPM is not running"
systemctl is-active --quiet mysql && print_success "MySQL is running" || print_error "MySQL is not running"

# Create summary file
cat > /root/wordpress-setup-summary.txt << EOF
===========================================
WORDPRESS SETUP SUMMARY
===========================================

Domain: $DOMAIN
WordPress Path: /var/www/blog
WordPress Admin URL: http://$DOMAIN/wp-admin

Database Information:
- Database Name: $WP_DB_NAME
- Database User: $WP_DB_USER
- Database Password: $WP_DB_PASSWORD
- MySQL Root Password: $MYSQL_ROOT_PASSWORD

WordPress Admin:
- Username: $WP_ADMIN_USER
- Password: $WP_ADMIN_PASSWORD
- Email: $WP_ADMIN_EMAIL

Important Commands:
- WordPress CLI: wp (already aliased)
- Backup: /root/wordpress-backup.sh
- Security Check: /root/wordpress-security.sh
- Reload Nginx: nginx-reload

Next Steps:
1. Set up DNS A record for $DOMAIN to server IP
2. Run: certbot --nginx -d $DOMAIN -d www.$DOMAIN
3. Login to WordPress admin and configure settings
4. Install additional plugins as needed

===========================================
EOF

print_success "WordPress setup completed successfully!"
print_status "Summary saved to: /root/wordpress-setup-summary.txt"
print_warning "IMPORTANT: Save these credentials securely!"
print_warning "WordPress Admin: $WP_ADMIN_USER / $WP_ADMIN_PASSWORD"
print_warning "MySQL Root Password: $MYSQL_ROOT_PASSWORD"

echo ""
print_status "To complete SSL setup, run:"
echo "certbot --nginx -d $DOMAIN -d www.$DOMAIN"

echo ""
print_status "Your WordPress site should be accessible at:"
echo "http://$DOMAIN"

print_success "Setup completed! Check /root/wordpress-setup-summary.txt for details."