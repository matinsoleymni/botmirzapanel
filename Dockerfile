# Use an official Ubuntu image as the base
FROM ubuntu:22.04

# Set the working directory
WORKDIR /var/www/html

# Update and upgrade the system
RUN apt update && apt upgrade -y

# Install necessary packages
RUN apt install -y \
    php8.2 \
    php8.2-fpm \
    php8.2-mysql \
    mysql-server \
    apache2 \
    php-mbstring \
    php-zip \
    php-gd \
    php-json \
    php-curl \
    php-soap \
    php-ssh2 \
    libssh2-1-dev \
    libssh2-1 \
    git \
    wget \
    unzip \
    curl \
    ufw \
    letsencrypt \
    python3-certbot-apache

# Add the Ondřej Surý PPA for PHP
RUN add-apt-repository -y ppa:ondrej/php || { \
    echo "Error: Failed to add PPA ondrej/php."; \
    exit 1; \
}

#Install phpMyAdmin
RUN echo 'phpmyadmin phpmyadmin/dbconfig-install boolean true' | debconf-set-selections
RUN echo 'phpmyadmin phpmyadmin/app-password-confirm password mirzahipass' | debconf-set-selections
RUN echo 'phpmyadmin phpmyadmin/mysql/admin-pass password mirzahipass' | debconf-set-selections
RUN echo 'phpmyadmin phpmyadmin/mysql/app-pass password mirzahipass' | debconf-set-selections
RUN echo 'phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2' | debconf-set-selections
RUN apt-get install -y phpmyadmin || { \
    echo "Error: Failed to install phpMyAdmin."; \
    exit 1; \
}

# Configure phpMyAdmin
RUN rm -f /etc/apache2/conf-available/phpmyadmin.conf || true
RUN ln -s /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf || { \
    echo "Error: Failed to create symbolic link for phpMyAdmin configuration."; \
    exit 1; \
}
RUN a2enconf phpmyadmin.conf || { \
    echo "Error: Failed to enable phpMyAdmin configuration."; \
    exit 1; \
}
RUN systemctl restart apache2 || { \
    echo "Error: Failed to restart Apache2 service."; \
    exit 1; \
}

# Enable and start MySQL service
RUN systemctl enable mysql.service || { \
    echo "Error: Failed to enable MySQL service."; \
    exit 1; \
}
RUN systemctl start mysql.service || { \
    echo "Error: Failed to start MySQL service."; \
    exit 1; \
}

# Enable and start Apache2 service
RUN systemctl enable apache2 || { \
    echo "Error: Failed to enable Apache2 service."; \
    exit 1; \
}
RUN systemctl start apache2 || { \
    echo "Error: Failed to start Apache2 service."; \
    exit 1; \
}

# Configure UFW
RUN ufw allow 'Apache' || { \
    echo "Error: Failed to allow Apache in UFW."; \
    exit 1; \
}
RUN ufw allow 80 || { \
    echo "Error: Failed to allow port 80 in UFW."; \
    exit 1; \
}
RUN ufw allow 443 || { \
    echo "Error: Failed to allow port 443 in UFW."; \
    exit 1; \
}

# Install Let's Encrypt and configure SSL
RUN apt install -y letsencrypt python3-certbot-apache || { \
    echo "Error: Failed to install letsencrypt."; \
    exit 1; \
}
RUN systemctl stop apache2 || { \
    echo "Error: Failed to stop Apache2."; \
    exit 1; \
}
RUN certbot certonly --standalone --agree-tos --preferred-challenges http -d ${DOMAIN_NAME} || { \
    echo "Error: Failed to generate SSL certificate."; \
    exit 1; \
}
RUN certbot --apache --agree-tos --preferred-challenges http -d ${DOMAIN_NAME} || { \
    echo "Error: Failed to configure SSL with Certbot."; \
    exit 1; \
}
RUN systemctl start apache2 || { \
    echo "Error: Failed to start Apache2."; \
    exit 1; \
}

# Clone the Mirza Bot repository
RUN git clone https://github.com/mahdiMGF2/botmirzapanel.git /var/www/html/mirzabotconfig || { \
    echo "Error: Failed to clone Git repository."; \
    exit 1; \
}

# Set ownership and permissions
RUN chown -R www-data:www-data /var/www/html/mirzabotconfig/
RUN chmod -R 755 /var/www/html/mirzabotconfig/

# Create and configure the database
RUN mkdir -p /root/confmirza || { \
    echo "Error: Failed to create /root/confmirza directory."; \
    exit 1; \
}
RUN touch /root/confmirza/dbrootmirza.txt || { \
    echo "Error: Failed to create dbrootmirza.txt."; \
    exit 1; \
}
RUN chmod -R 777 /root/confmirza/dbrootmirza.txt || { \
    echo "Error: Failed to set permissions for dbrootmirza.txt."; \
    exit 1; \
}

# Generate random database credentials
RUN randomdbpasstxt=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9' | cut -c1-8)
RUN echo "user = 'root'; pass = '${randomdbpasstxt}'; path = '${RANDOM_NUMBER}';" >> /root/confmirza/dbrootmirza.txt

# Configure MySQL
RUN mysql -u root -p${randomdbpasstxt} -e "alter user 'root'@'localhost' identified with mysql_native_password by '${randomdbpasstxt}'; FLUSH PRIVILEGES;" || { \
    echo "Error: Failed to alter MySQL user. Attempting recovery..."; \
    # Recovery steps can be added here if needed \
}

# Create the database and user
RUN dbname=mirzabot
RUN dbuser=$(openssl rand -base64 10 | tr -dc 'a-zA-Z' | cut -c1-8)
RUN dbpass=$(openssl rand -base64 10 | tr -dc 'a-zA-Z0-9' | cut -c1-8)
RUN mysql -u root -p${randomdbpasstxt} -e "CREATE DATABASE ${dbname}; CREATE USER '${dbuser}'@'%' IDENTIFIED WITH mysql_native_password BY '${dbpass}'; GRANT ALL PRIVILEGES ON *.* TO '${dbuser}'@'%'; FLUSH PRIVILEGES;" || { \
    echo "Error: Failed to create database or user."; \
    exit 1; \
}

# Configure the config.php file
RUN echo "<?php" >> /var/www/html/mirzabotconfig/config.php
RUN echo "APIKEY = 'YOUR_BOT_TOKEN';" >> /var/www/html/mirzabotconfig/config.php
RUN echo "usernamedb = '${dbuser}';" >> /var/www/html/mirzabotconfig/config.php
RUN echo "passworddb = '${dbpass}';" >> /var/www/html/mirzabotconfig/config.php
RUN echo "dbname = '${dbname}';" >> /var/www/html/mirzabotconfig/config.php
RUN echo "domainhosts = 'YOUR_DOMAIN/mirzabotconfig';" >> /var/www/html/mirzabotconfig/config.php
RUN echo "adminnumber = 'YOUR_CHAT_ID';" >> /var/www/html/mirzabotconfig/config.php
RUN echo "usernamebot = 'YOUR_BOTNAME';" >> /var/www/html/mirzabotconfig/config.php
RUN echo "connect = mysqli_connect('localhost', \$usernamedb, \$passworddb, \$dbname);" >> /var/www/html/mirzabotconfig/config.php
RUN echo "if (\$connect->connect_error) {" >> /var/www/html/mirzabotconfig/config.php
RUN echo "die(' The connection to the database failed:' . \$connect->connect_error);" >> /var/www/html/mirzabotconfig/config.php
RUN echo "}" >> /var/www/html/mirzabotconfig/config.php
RUN echo "mysqli_set_charset(\$connect, 'utf8mb4');" >> /var/www/html/mirzabotconfig/config.php

# Set environment variables for Telegram Bot Token, Chat ID, Domain, and Bot Name
ENV YOUR_BOT_TOKEN="7327077875:AAG9DfzjRwigtGY9B1pmq2JUQ-WkK-duerw"
ENV YOUR_CHAT_ID="691903008"
ENV YOUR_DOMAIN="robot1.phppanel5.top"
ENV YOUR_BOTNAME="ServerBot"

# Expose ports
EXPOSE 80
EXPOSE 443

# Start services when the container starts
CMD ["systemctl", "start", "apache2"] && ["systemctl", "start", "mysql"]
