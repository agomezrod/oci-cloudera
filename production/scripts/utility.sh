# Install instructions are here: https://www.cloudera.com/documentation/enterprise/6/6.0/topics/install_cm_cdh.html

# Step 1: Configure a Repository
wget https://archive.cloudera.com/cm6/6.0.1/redhat7/yum/cloudera-manager.repo -P /etc/yum.repos.d/
rpm --import https://archive.cloudera.com/cm6/6.0.1/redhat7/yum/RPM-GPG-KEY-cloudera

# Step 2: Install JDK
yum install -y oracle-j2sdk1.8

# Step 3: Install Cloudera Manager Server
yum install -y cloudera-manager-daemons cloudera-manager-agent cloudera-manager-server

# Step 4: Install Databases
yum install -y postgresql-server
yum install -y python-pip
pip install --upgrade pip
pip install psycopg2==2.7.5 --ignore-installed

# Step 4.1: Make sure that LC_ALL is set to en_US.UTF-8 and initialize the database
echo 'LC_ALL="en_US.UTF-8"' >> /etc/locale.conf
su -l postgres -c "postgresql-setup initdb"

# Step 4.2: Enable MD5 authentication.
sed -i '/host.*127.*ident/i \
host    all         all         127.0.0.1/32          md5  \ ' /var/lib/pgsql/data/pg_hba.conf

# Step 4.3: Configure settings to ensure your system performs as expected.
/var/lib/pgsql/data/postgresql.conf

/opt/cloudera/cm/schema/scm_prepare_database.sh postgresql scm scm scm

# Step 4.4: Configure the PostgreSQL server to start at boot.
systemctl enable postgresql
systemctl restart postgresql

# Creating Databases for Cloudera Software
# Step 5: Set up the Cloudera Manager Database

# Step 6: Install CDH and Other Software
#systemctl start cloudera-scm-server

# Step 7: Set Up a Cluster
