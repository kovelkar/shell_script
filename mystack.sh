#!/bin/bash

R="\e[31m";G="\e[32m";Y="\e[33m";B="\e[34m";M="\e[35m";C="\e[36m";N="\e[0m"
LOG=/tmp/error.log
user_id=$(id -u)
TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.6/bin/apache-tomcat-9.0.6.tar.gz"
TOMCAT_DIR=$(echo $TOMCAT_URL | awk -F / '{print $NF}'|sed -e 's/.tar.gz//')
APP_URL="https://github.com/cit-aliqui/APP-STACK/raw/master/student.war"
Connector_URL="https://github.com/cit-aliqui/APP-STACK/raw/master/mysql-connector-java-5.1.40.jar"
CONTEXT_STRING='<Resource name="jdbc/TestDB" auth="Container" type="javax.sql.DataSource" maxActive="50" maxIdle="30" maxWait="10000" username="student" password="student@1" driverClassName="com.mysql.jdbc.Driver" url="jdbc:mysql://IPADDR:3306/studentapp"/>'
IPADDR=$(hostname -i)
CONTEXT_STRING=$(echo $CONTEXT_STRING | sed -e "s/IPADDR/$IPADDR/")
HTTP_CONNECTOR_URL="http://www-us.apache.org/dist/tomcat/tomcat-connectors/jk/tomcat-connectors-1.2.44-src.tar.gz"
HTTP_CONNECTOR_DIR=$(echo $HTTP_CONNECTOR_URL | awk -F / '{print $NF}'| sed -e 's/.tar.gz//')


if [ $user_id -ne 0 ]; then
    echo -e "${R}You need to be root user to perform this task ${N}"
    exit
fi

head_color(){
    echo -e "${M}$1${N}"
}

info(){
 echo -n -e "\t${C}$1${N} - "
}

status(){
    if [ $1 -eq 0 ]; then
        echo -e "${G}Success${N}"
    else
        echo -e "${R} \t Failure : Please refer $LOG for error log ${N} "
        exit
    fi
}

DBF(){
    head_color 'DataBase Setup : '
    info 'Installing Maria DB'
    yum install mariadb-server -y &>>$LOG
    status $?

    info 'Starting Maria DB'
    systemctl enable mariadb &>$LOG
    systemctl start mariadb &>>$LOG
    status $?

    info 'Configuration of DataBase and table'
    echo "create database if not exists studentapp;
    use studentapp;
    CREATE TABLE if not exists Students(student_id INT NOT NULL AUTO_INCREMENT,
        student_name VARCHAR(100) NOT NULL,
        student_addr VARCHAR(100) NOT NULL,
	    student_age VARCHAR(3) NOT NULL,
	    student_qual VARCHAR(20) NOT NULL,
	    student_percent VARCHAR(10) NOT NULL,
	    student_year_passed VARCHAR(10) NOT NULL,
	    PRIMARY KEY (student_id)
        );
        grant all privileges on studentapp.* to 'student'@'%' identified by 'student@1';
        flush privileges; " >/tmp/student.sql

    mysql < /tmp/student.sql &>>$LOG
    status $?


}

APPF(){
    head_color 'AppServer Setup'
    info 'Installing Java '
    yum install java -y &>>$LOG
    status $?
    info 'Downloading Apache Tomcat server '
    if [ -d $TOMCAT_DIR ]; then
        echo "already exists"
    else
       wget -qO- $TOMCAT_URL| tar -xz &>>$LOG
       status $?
    fi
    info 'Adding student app to webapps'
    rm -rf $TOMCAT_DIR/webapps/*  
    wget  $APP_URL -O $TOMCAT_DIR/webapps/student.war&>>$LOG
    status $?
    info 'Downloading MySQL Connector jar'
    wget $Connector_URL -O $TOMCAT_DIR/lib/mysql-connector-java-5.1.40.jar &>>$LOG
    status $?
    info 'Configuring context.xml '
    sed -i -e '/TestDB/ d' -e "$ i $CONTEXT_STRING" $TOMCAT_DIR/conf/context.xml
    ps -ef | grep tomcat |grep -v grep &>>$LOG
    if [ $? -eq 0 ];then
        echo   -n "stopping tomcat"
        $TOMCAT_DIR/bin/shutdown.sh sh &>>$LOG
        status $?
    fi
    echo -n "starting tomcat"
    $TOMCAT_DIR/bin/startup.sh sh &>>$LOG
    status $?
    
}

WEBF(){
    head_color 'WebServer Setup'
    info "Installing Tomcat HTTP server"
    yum install httpd -y &>>$LOG
    status $?
    info "Downloading HTTP connector"
    wget -qO- $HTTP_CONNECTOR_URL | tar -xz &>>$LOG
    status $?
    info "Installing HTTPD Devel"
    yum  install httpd-devel gcc -y &>>$LOG
    status $?
    info "Configuring HTTPD devel"
    cd $HTTP_CONNECTOR_DIR/native
    ./configure --with-apxs=/usr/bin/apxs &>>$LOG
    make &>>$LOG
    status $?
    info "Genarating mod_jk.so"
    make install &>>$LOG
    status $?
    info "mod-jk.conf"
    #echo 'LoadModule jk_module modules/mod_jk.so

    #JkWorkersFile /etc/httpd/conf.d/worker.properties
    #JkMount /student local
    #JkMount /student/* local' > /etc/httpd/conf.d/mod-jk.conf

    echo 'LoadModule jk_module modules/mod_jk.so

    JkWorkersFile /etc/httpd/conf.d/worker.properties
    JkMount /student local
    JkMount /student/* local' > /etc/httpd/conf.d/mod-jk.conf
    status $?
    info "worker.properties"
    echo 'worker.list=local
    worker.local.host=localhost
    worker.local.port=8009' > /etc/httpd/conf.d/worker.properties
    status $?
    info "Starting HTTP server"
    systemctl stop httpd &>>$LOG
    systemctl enable httpd &>>$LOG
    systemctl start httpd &>>$LOG
    status $?
}

read  -p "Select the component to install DB|APP|WEB|ALL :" comp
case $comp in 
    DB)  DBF ;;
    APP) APPF ;;
    WEB) WEBF ;;
    ALL) DBF;APPF;WEBF;;
    *) echo "Please choose a component to install"
       exit 1;;
esac