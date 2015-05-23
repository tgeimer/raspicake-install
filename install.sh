#!/bin/bash

############################################################################
# File:         install.sh
# Author:       Thomas Geimer
# Purpose:      This script will configure a newly-imaged Raspberry Pi running
#               Raspbian Wheezy (tested version 2015-02-16) with the software
#               needed for RaspiCake Web Management
#
# Prerequisites:
# This script assumes, that you have executed "raspi-config" and configured:
# 1. expand filesystem
# 2. enable ssh
# 3. enable camera
# 4. set locale, keyboard layout, etc
# 6. you have executed "sudo rpi-update"
# 7. you have executed "sudo apt-get update && sudo apt-get upgrade -y"
#    to have your raspberry pi up to date and the current repositories
#
############################################################################

PROJECT=raspicake
CWD=$(pwd)
INSTALL_LOG=$CWD/raspicake_install.log
FINAL_RC=0
RC=0
RESULT=""

# Colors:
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # reset color

on_die() {
  echo "Interrupting..."
  echo "Interrupting" >> $INSTALL_LOG
  exit 1
}
trap 'on_die' TERM
trap 'on_die' KILL
trap 'on_die' INT

# Script must be run as root (or as user pi with "sudo")
if [ $(whoami) != "root" ]; then
  printf "${RED}ERROR${NC}: This script must be run with root privileges. \nTry${BLUE}sudo %s${NC} instead\n" $0
  on_die
fi

# function to check the return code of a command:
checkrc()
{
  RC=$1
  if [ $RC -eq 0 ]; then
    RESULT="[${GREEN}OK${NC}]";
  else
    RESULT="[${RED}ERROR${NC}] RC=$RC";
    FINAL_RC=$(expr $FINAL_RC + 1)
  fi
}

# convenience function to install precompiled packages:
packet_install(){
  PACKETNAME=$1
  printf "%s\tinstalling %s..." $(date +%H:%M:%S) $PACKETNAME
  printf "%s\tinstalling %s..." $(date +%H:%M:%S) $PACKETNAME >> $INSTALL_LOG
  if [ $(dpkg -l | grep -F " $PACKETNAME " | wc -l) -gt 0 ]; then
    printf "[already installed]\n" >> $INSTALL_LOG
    printf "[${GREEN}already installed${NC}]\n"
  else
    apt-get install -y $PACKETNAME
    checkrc $? && printf "%s\n" "$RESULT" >> $INSTALL_LOG
    printf "%s\n" "$RESULT"
  fi
}
# ======================= INSTALLATION =========================

# -------------- Interaction ----------------------------------
PROJECT_EXISTS=1;
while [ $PROJECT_EXISTS -eq 1 ]; do
  PROJECT=$(whiptail --inputbox "Please enter a project name" 20 60 "$PROJECT" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    printf "${RED}Installation aborted.${NC}\n" $PROJECT
    on_die
  fi
  if [ -d /usr/share/$PROJECT ]; then
    whiptail  --title "ERROR" --msgbox "ERROR: /usr/share/$PROJECT already exists. please choose another name.\n" 20 60
    PROJECT_EXISTS=1
  else
    PROJECT_EXISTS=0
  fi
done
  
# set MySQL root Password:
#TODO: generate randomly
PW_EQUAL=0
while [ $PW_EQUAL -eq 0 ]; do
  MYSQL_ROOT_PW1=$(whiptail --inputbox "Please enter the password of your MySQL root user:" 20 60 "$PROJECT" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    printf "${RED}Installation aborted.${NC}\n" $PROJECT
    on_die
  fi
  MYSQL_ROOT_PW2=$(whiptail --inputbox "Please confirm the MySQL root password:" 20 60 "$PROJECT" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    printf "${RED}Installation aborted.${NC}\n" $PROJECT
    on_die
  fi

  if [ "$MYSQL_ROOT_PW1" == "$MYSQL_ROOT_PW2" ]; then
    PW_EQUAL=1;
  else
    whiptail --title "ERROR: password mismatch" --msgbox "The passwords do not match, please try again." 20 60
  fi
done

# set MySQL DB name, user and Password:
MYSQL_DBNAME=$(whiptail --inputbox "Please enter the DB name for the web app:" 20 60 "$PROJECT" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
  printf "${RED}Installation aborted.${NC}\n" $PROJECT
  on_die
fi
MYSQL_USER=$(whiptail --inputbox "Please enter the DB username for the web app:" 20 60 "$PROJECT" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
  printf "${RED}Installation aborted.${NC}\n" $PROJECT
  on_die
fi
PW_EQUAL=0
while [ $PW_EQUAL -eq 0 ]; do
  MYSQL_USER_PW1=$(whiptail --inputbox "Please enter the password for DB user $MYSQL_USER:" 20 60 "$PROJECT" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    printf "${RED}Installation aborted.${NC}\n" $PROJECT
    on_die
  fi
  MYSQL_USER_PW2=$(whiptail --inputbox "Please confirm the MySQL $MYSQL_USER user password:" 20 60 "$PROJECT" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    printf "${RED}Installation aborted.${NC}\n" $PROJECT
    on_die
  fi

  if [ "$MYSQL_USER_PW1" == "$MYSQL_USER_PW2" ]; then
    PW_EQUAL=1;
  else
    whiptail --title "ERROR: password mismatch" --msgbox "The passwords do not match, please try again." 20 60
  fi
done

printf "%s\t%s installation starting \n\n" $(date +%H:%M:%S) $PROJECT
printf "%s\t%s installation starting \n\n..." $(date +%H:%M:%S) $PROJECT > $INSTALL_LOG

if [ ! -d /usr/share/$PROJECT ]; then
  mkdir /usr/share/$PROJECT
else
  printf "[${RED}ERROR${NC}] /usr/share/%s already exists. please choose another name.\n" $PROJECT
  on_die
fi

# -------------- install nginx webserver (web administration) ------
packet_install nginx
# --------------- install PHP5 with several modules --------------
packet_install php5-fpm
packet_install php5-mcrypt
packet_install php5-gd
packet_install php-apc
packet_install php5-cli
packet_install php5-intl
packet_install php5-mysql

# --------------- install MySQL --------------
if [ ! $(which mysql) ]; then
  debconf-set-selections <<< 'mysql-server mysql-server/root_password password $MYSQL_ROOT_PW1'
  debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PW2'
fi
packet_install mysql-server
# --------------- create Database ---
printf "%s\tcreating database..." $(date +%H:%M:%S)
printf "%s\tcreating database..." $(date +%H:%M:%S) >> $INSTALL_LOG
if [ $(mysql -u root -p"$MYSQL_ROOT_PW1" -e "show databases;" | grep $MYSQL_DBNAME | wc -l) -eq 1 ]; then
  printf "[already exists]\n" >> $INSTALL_LOG
  printf "[${GREEN}already exists${NC}]\n"
else
  mysql -u root -p"$MYSQL_ROOT_PW1" -e "create database $MYSQL_DBNAME;"
  checkrc $? && printf "%s\n" "$RESULT" >> $INSTALL_LOG
  printf "%s\n" "$RESULT"
fi

# --------------- create DB user ---
printf "%s\tcreating DB user..." $(date +%H:%M:%S)
printf "%s\tcreating DB user..." $(date +%H:%M:%S) >> $INSTALL_LOG
if [ $(mysql -u root -p"$MYSQL_ROOT_PW1" -e "SELECT User FROM mysql.user;" --batch | grep $MYSQL_USER | wc -l) -gt 0 ]; then
  printf "[already exists]\n" >> $INSTALL_LOG
  printf "[${GREEN}already exists${NC}]\n"
else
  mysql -u root -p"$MYSQL_ROOT_PW1" -e "DROP USER '$MYSQL_USER'@'localhost';CREATE USER '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_USER_PW1'; GRANT ALL ON $MYSQL_DBNAME.* TO '$MYSQL_USER'@'localhost'; FLUSH PRIVILEGES;"
  checkrc $? && printf "%s\n" "$RESULT" >> $INSTALL_LOG
  printf "%s\n" "$RESULT"
fi

# ----------------- WiringPi Library -------------
# install WiringPi library by @Drogon.
# This is used for convenient control of the GPIO pins:
printf "%s\tInstalling WiringPi..." $(date +%H:%M:%S)
printf "%s\tInstalling WiringPi..." $(date +%H:%M:%S) >> $INSTALL_LOG
if [ $(which gpio) ]; then
  printf "[already installed]\n" >> $INSTALL_LOG
  printf "[${GREEN}already installed${NC}]\n"
else
  cd /usr/share
  git clone git://git.drogon.net/wiringPi
  cd wiringPi
  ./build
  checkrc $? && printf "%s\n" "$RESULT" >> $INSTALL_LOG
  printf "%s\n" "$RESULT"
  cd $CWD
fi


# -------------- configure nginx webserver (web administration) ------
printf "%s\tconfiguring /etc/nginx/nginx.conf..." $(date +%H:%M:%S)
printf "%s\tconfiguring /etc/nginx/nginx.conf..." $(date +%H:%M:%S) >> $INSTALL_LOG
if [ ! -f /etc/nginx/nginx.conf.default ]; then
  # backup default nginx.conf
  cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.default
  # make some adjustments to save resources:
  sed -i "s/worker_processes 4;/worker_processes 1;/g" /etc/nginx/nginx.conf
  sed -i "s/worker_connections 768;/worker_connections 128;/g" /etc/nginx/nginx.conf
  checkrc $? && printf "%s\n" "$RESULT" >> $INSTALL_LOG
  printf "%s\n" $RESULT
else
  printf "[already configured]\n" >> $INSTALL_LOG
  printf "[${GREEN}already configured${NC}]\n"
fi
FINAL_RC=($FINAL_RC + $RC)

# --------------- create a wopi site for nginx -----------------
printf "%s\tcreating nginx site for wopi..." $(date +%H:%M:%S)
printf "%s\tcreating nginx site for wopi..." $(date +%H:%M:%S) >> $INSTALL_LOG
_IP=$(hostname -I)
if [ ! -f /etc/nginx/sites-available/$PROJECT ]; then
  cat <<EOT > /etc/nginx/sites-available/$PROJECT
server {
    listen 80;
    server_name RASPI_IP;
    rewrite 301 http://RASPI_IP\$request_uri permanent;

        #root directive should be global
    root /usr/share/nginx/www/PROJECT/webroot/;
    index  index.php index.html index.htm;

    access_log /var/log/access.log;
    error_log /var/log/error.log;

    location / {
        try_files \$uri /index.php?\$arXXXgs;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php5-fpm.sock;
        include fastcgi_params;
        include /etc/nginx/fastcgi_params;
        fastcgi_index index.php;
    }
}

EOT

  # now replace some placeholders with variables:
  sed -i "s/RASPI_IP/$(hostname -I | tr -d '[[:space:]]')/g" /etc/nginx/sites-available/$PROJECT
  sed -i "s/PROJECT/$PROJECT/g" /etc/nginx/sites-available/$PROJECT
  sed -i "s/arXXXgs/args/g" /etc/nginx/sites-available/$PROJECT

  if [ -f /etc/nginx/sites-available/$PROJECT ]; then
    printf "[OK]\n" >> $INSTALL_LOG
    printf "[$(tput setaf 2)OK${NC}]\n"
  else
    printf "[ERROR] file not found\n" >> $INSTALL_LOG
    printf "[$(tput setaf 1)[ERROR]${NC}]\n"
  fi
fi
# If a default site is enabled: disable it
if [ -L /etc/nginx/sites-enabled/default ]; then
  rm /etc/nginx/sites-enabled/default
fi
# check if the $PROJECT site is enabled:
if [ -L /etc/nginx/sites-enabled/$PROJECT ]; then
  printf "[already enabled]\n" >> $INSTALL_LOG
  printf "[${GREEN}already enabled${NC}]\n"
else
  ln -s /etc/nginx/sites-available/$PROJECT /etc/nginx/sites-enabled/$PROJECT
  printf "[enabled]\n" >> $INSTALL_LOG
  printf "[${GREEN}enabled${NC}]\n"
fi


# ======================= CakePHP 3.0 ================================
# ------------------- install Composer globally -------------------------------
printf "%s\tinstalling Composer..." $(date +%H:%M:%S)
printf "%s\tinstalling Composer..." $(date +%H:%M:%S) >> $INSTALL_LOG
if [ ! $(which composer) ]; then
  curl -s https://getcomposer.org/installer | php >> /dev/null 2>&1
  checkrc $? && printf "%s\n" "$RESULT" >> $INSTALL_LOG
  printf "%s\n" $RESULT
  mv composer.phar /usr/local/bin/composer
else
  printf "[already installed]\n" >> $INSTALL_LOG
  printf "[${GREEN}already installed${NC}]\n"
fi

# ------------------- install CakePHP 3.0 -------------------------------
printf "%s\tinstalling RaspiCake app..." $(date +%H:%M:%S)
printf "%s\tinstalling RaspiCake app..." $(date +%H:%M:%S) >> $INSTALL_LOG
if [ ! -f /usr/share/nginx/www/$PROJECT/webroot/index.php ]; then
  composer create-project -s dev --prefer-dist tgeimer/raspicake /usr/share/nginx/www/$PROJECT --no-interaction >> /dev/null 2>&1
  checkrc $? && printf "%s\n" "$RESULT" >> $INSTALL_LOG
  printf "%s\n" $RESULT
else
  printf "[already installed]\n" >> $INSTALL_LOG
  printf "[${GREEN}already installed${NC}]\n"
fi

# ------------------- Set permissions ---------------------------
printf "%s\tsetting CakePHP permissions..." $(date +%H:%M:%S)
printf "%s\tsetting CakePHP permissions..." $(date +%H:%M:%S) >> $INSTALL_LOG
PROJECT_OWNER=$(ls -l /usr/share/nginx/www | grep $PROJECT | cut -d " " -f 3)
if [ "$PROJECT_OWNER" != "pi" ]; then
  sudo chown -R pi:www-data /usr/share/nginx/www/$PROJECT
  checkrc $? && printf "%s\n" "$RESULT" >> $INSTALL_LOG
  printf "%s\n" $RESULT
else
  printf "[already correct]\n" >> $INSTALL_LOG
  printf "[${GREEN}already correct${NC}]\n"
fi
# force tmp and log directories to be writable
if [ -d /usr/share/nginx/www/$PROJECT ]; then
  chmod -R 775 /usr/share/nginx/www/$PROJECT/tmp
  chmod -R 775 /usr/share/nginx/www/$PROJECT/logs
fi
  
# ------------------- configure database connection -------------
if [ -f /usr/share/nginx/www/$PROJECT/config/app.php ]; then
  sed -i s,"MYSQL_USER","$MYSQL_USER",g /usr/share/nginx/www/$PROJECT/config/app.php
  sed -i s,"MYSQL_USER_PW","$MYSQL_USER_PW1",g /usr/share/nginx/www/$PROJECT/config/app.php
  sed -i s,"MYSQL_DBNAME","$MYSQL_DBNAME",g /usr/share/nginx/www/$PROJECT/config/app.php
fi

# ------------------- populating DB ---------------------------
printf "%s\tpopulating database..." $(date +%H:%M:%S)
printf "%s\tpopulating database..." $(date +%H:%M:%S) >> $INSTALL_LOG
SQL_OUTPUT=$(mysql -u $MYSQL_USER --password="$MYSQL_USER_PW1" $MYSQL_DBNAME -e "show tables;" 2>&1)
RC=$?
if [ $RC -eq 0 ];then
  if [ -f /usr/share/nginx/www/$PROJECT/config/schema/raspicake.sql ]; then
    mysql -u $MYSQL_USER --password="$MYSQL_USER_PW1" $MYSQL_DBNAME < /usr/share/nginx/www/$PROJECT/config/schema/raspicake.sql
	checkrc $? && printf "%s\n" "$RESULT" >> $INSTALL_LOG
    printf "%s\n" $RESULT
  else
    FINAL_RC=$(expr $FINAL_RC + 1);
    printf "[ERROR] /usr/share/nginx/www/%s/config/schema/raspicake.sql not found\n" $PROJECT >> $INSTALL_LOG
    printf "[${RED}ERROR${NC}] /usr/share/nginx/www/%s/config/schema/raspicake.sql not found\n" $PROJECT
  fi
else
  FINAL_RC=$(expr $FINAL_RC + 1);
  printf "[ERROR]\n$SQL_OUTPUT\n" >> $INSTALL_LOG
  printf "[${RED}ERROR${NC}]\n$SQL_OUTPUT\n"
fi
  
printf "\n%s\t$PROJECT installation finished with %s errors\n\n" $(date +%H:%M:%S) $FINAL_RC >> $INSTALL_LOG
printf "\n%s\t$PROJECT installation finished with %s errors\n\n" $(date +%H:%M:%S) $FINAL_RC

service php5-fpm restart
service nginx restart

printf "\n\nDONE!\n\n" >> $INSTALL_LOG
printf "\n\nDONE!\n\n"

exit $FINAL_RC
