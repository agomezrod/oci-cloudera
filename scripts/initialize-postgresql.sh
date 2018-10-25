LOG_FILE="/var/log/cloudera-OCI-initialize.log"

# manually set EXECNAME because this file is called from another script and it $0 is "bash"
EXECNAME="initialize-postgresql.sh"
CURRENT_VERSION_MARKER='OCI_1'
SLEEP_INTERVAL=5

# logs everything to the $LOG_FILE
log() {
  echo "$(date) [${EXECNAME}]: $*" >> "${LOG_FILE}"
}

stop_db()
{
  sudo service postgresql stop
}

fail_or_continue()
{
  local RET=$1
  local STR=$2

  if [[ $RET -ne 0 ]]; then
    stop_db
    if [[ -z $STR ]]; then
      STR="--> Error $RET"
    fi
    log "$STR, giving up"
    log "------- initialize-postgresql.sh failed -------"
    exit "$RET"
  fi
}

create_database()
{
  local DB_CMD="sudo -u postgres psql"
  local DBNAME=$1
  local PW=$2
  local ROLE=$DBNAME

  #if pass in the third parameter, us it as the ROLE name
  if ! [ -z "$3" ];then
    local ROLE=$3
    echo "$3, $ROLE"
  fi
  echo "$ROLE"

  echo "CREATE ROLE $ROLE LOGIN PASSWORD '$PW';"
  $DB_CMD --command "CREATE ROLE $ROLE LOGIN PASSWORD '$PW';"
  fail_or_continue $? "Unable to create database role $ROLE"
  echo "CREATE DATABASE $DBNAME OWNER $ROLE;"
  $DB_CMD --command "CREATE DATABASE $DBNAME OWNER $ROLE;"
  fail_or_continue $? "Unable to create database $DBNAME"
}

# Returns 0 if the given DB exists in the DB list file.
db_exists()
{
  grep -q -s -e "^$1$" "$DB_LIST_FILE"
}

create_random_password()
{
  perl -le 'print map { ("a".."z", "A".."Z", 0..9)[rand 62] } 1..10'
}

# Creates the SCM database, if it doesn't exist yet.
create_scm_db()
{
  if db_exists scm; then
    return 0
  fi

  local PW=$1
  create_database scm "$PW"

  orig_umask=$(umask)
  umask 0077
  echo "Creating SCM configuration file: $DB_PROP_FILE"
  cat > "$DB_PROP_FILE" << EOF
# Auto-generated by `basename $0`
#
# $NOW
#
# These are database settings for CM Manager
#
com.cloudera.cmf.db.type=postgresql
com.cloudera.cmf.db.host=localhost:$DB_PORT
com.cloudera.cmf.db.name=scm
com.cloudera.cmf.db.user=scm
com.cloudera.cmf.db.password=$PW
EOF

  umask "$orig_umask"
  fail_or_continue $? "Error creating file $DB_PROP_FILE"
  echo "Created db properties file $DB_PROP_FILE"
  backup_file "$DB_LIST_FILE"
  echo scm >> "$DB_LIST_FILE"
}

create_hive_metastore()
{
  # $1 is the MgmtServiceHandler.RoleNames Enum value
  # $2 is the database name.
  # hive has different db name and role name
  local role='HIVEMETASTORESERVER'
  local db='metastore'
  local hive='hive'
  if db_exists $db; then
    return 0
  fi

  echo "Creating DB $db for role $role"
  local pw
  pw=$(create_random_password)
  create_database "$db" "$pw" "$hive"

  echo "host    $db $hive  0.0.0.0/0   md5" >> "$DATA_DIR"/pg_hba.conf

  if [[ $MGMT_DB_MODIFIED -eq 0 ]]; then
    backup_file "$MGMT_DB_PROP_FILE"
  fi
  MGMT_DB_MODIFIED=1

  # Write the prop file header.
  if [[ ! -f $MGMT_DB_PROP_FILE ]]; then
    orig_umask=$(umask)
    umask 0077
    cat > "$MGMT_DB_PROP_FILE" << EOF
# Auto-generated by `basename $0`
#
# $NOW
#
# These are database credentials for databases
# created by "cloudera-scm-server-db" for
# Cloudera Manager Management Services,
# to be used during the installation wizard if
# the embedded database route is taken.
#
# The source of truth for these settings
# is the Cloudera Manager databases and
# changes made here will not be reflected
# there automatically.
#
EOF

    umask "$orig_umask"
    fail_or_continue $? "Error creating file $MGMT_DB_PROP_FILE"
  fi

  local PREFIX="com.cloudera.cmf.$role.db"

  # Append the role db properties to the mgmt db props file.
  cat >> "$MGMT_DB_PROP_FILE" <<EOF
$PREFIX.type=postgresql
$PREFIX.host=$DB_HOSTPORT
$PREFIX.name=$db
$PREFIX.user=$hive
$PREFIX.password=$pw
EOF
  fail_or_continue $? "Error updating file $MGMT_DB_PROP_FILE"

  # Update pg_hba.conf for the new database.
  echo "host    $db   $hive   0.0.0.0/0   md5" >> "$DATA_DIR"/pg_hba.conf

  echo "Created DB for role $role"
  backup_file "$DB_LIST_FILE"
  echo "$db" >> "$DB_LIST_FILE"
}


# Creates a database for a specific role, if it doesn't exist yet.
create_mgmt_role_db()
{
  # $1 is the MgmtServiceHandler.RoleNames Enum value
  # $2 is the database name.
  local role=$1
  local db=$2
  if db_exists "$db"; then
    return 0
  fi

  echo "Creating DB $db for role $role"
  local pw
  pw=$(create_random_password)
  create_database "$db" "$pw"

  if [[ $MGMT_DB_MODIFIED -eq 0 ]]; then
    backup_file "$MGMT_DB_PROP_FILE"
  fi
  MGMT_DB_MODIFIED=1

  # Write the prop file header.
  if [[ ! -f $MGMT_DB_PROP_FILE ]]; then
    orig_umask=$(umask)
    umask 0077
    cat > "$MGMT_DB_PROP_FILE" << EOF
# Auto-generated by `basename $0`
#
# $NOW
#
# These are database credentials for databases
# created by "cloudera-scm-server-db" for
# Cloudera Manager Management Services,
# to be used during the installation wizard if
# the embedded database route is taken.
#
# The source of truth for these settings
# is the Cloudera Manager databases and
# changes made here will not be reflected
# there automatically.
#
EOF

    umask "$orig_umask"
    fail_or_continue $? "Error creating file $MGMT_DB_PROP_FILE"
  fi

  local PREFIX="com.cloudera.cmf.$role.db"

  # Append the role db properties to the mgmt db props file.
  cat >> "$MGMT_DB_PROP_FILE" <<EOF
$PREFIX.type=postgresql
$PREFIX.host=$DB_HOSTPORT
$PREFIX.name=$db
$PREFIX.user=$db
$PREFIX.password=$pw
EOF
  fail_or_continue $? "Error updating file $MGMT_DB_PROP_FILE"

  # Update pg_hba.conf for the new database.
  echo "host    $db   $db   0.0.0.0/0   md5" >> "$DATA_DIR"/pg_hba.conf

  echo "Created DB for role $role"
  backup_file "$DB_LIST_FILE"
  echo "$db" >> "$DB_LIST_FILE"
}

pg_hba_contains()
{
  grep -q -s -e "^$1$" "$DATA_DIR"/pg_hba.conf
}

# changes postgres config to allow remote connections. Idempotent.
configure_remote_connections()
{
  local FIRSTLINE="# block remote access for admin user"
  local SECONDLINE="host    all    postgres 0.0.0.0/0 reject"
  local THIRDLINE="# enable remote access for other users"
  local FOURTHLINE="host    sameuser all  0.0.0.0/0   md5"

  if pg_hba_contains "$FIRSTLINE"; then
    return 0
  fi
  # Update pg_hba.conf for the new database.
  echo "$FIRSTLINE" >> "$DATA_DIR"/pg_hba.conf
  echo "$SECONDLINE" >> "$DATA_DIR"/pg_hba.conf
  echo "$THIRDLINE" >> "$DATA_DIR"/pg_hba.conf
  echo "$FOURTHLINE" >> "$DATA_DIR"/pg_hba.conf

  echo "Enabled remote connections"
}

# Get the amount of RAM on the system. Uses "free -b" to get the amount
# in bytes and parses the output to get total amount of memory available.
get_system_ram()
{
  local free_output
  free_output=$(free -b | grep Mem)
  local regex="Mem:[[:space:]]+([[:digit:]]+)"
  if [[ $free_output =~ $regex ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    fail_or_continue 1 "Unable to find amount of RAM on the system"
  fi
}

# We need to set a good value for postgresql shared_buffer parameter. Default
# is 32 MB which is too low. Postgresql recommends setting this to 1/4 of RAM
# if there is more than 1GB of RAM on the system (which is true for most systems
# today). This parameter also depends on the Linux maximum shared memory parameter
# (cat /proc/sys/kernel/shmmax)
# Few linux systems default the shmmax to 32 MB, below that level we should let
# postgresql default as is. Above this value, we will use 50% of the shmmax as
# the shared_buffer default value. Also maximum recommended value is 8GB, so
# we will ceil on 8 GB.
#
# shared_buffer is specified in kernel buffer cache block size, typically
# 1024 bytes (8192 bits). So the shared_buffer value * 8192 gives the memory
# in bits that will be used (actually table 17-2 of postgresql doc says that
# it should be 8192 + 208: http://www.postgresql.org/docs/9.1/static/kernel-resources.html)
#
get_shared_buffers()
{
  local ram
  ram=$(get_system_ram)
  local shmmax
  shmmax=$(cat /proc/sys/kernel/shmmax)
  local THIRTY_TWO_MB=$((32 * 1024 * 1024))
  local EIGHT_GB=$((8 * 1024 * 1024 * 1024))
  local SIXTEEN_GB=$((16 * 1024 * 1024 * 1024))
  local shared_buffer;

  # On some systems we get value of shmmax that is out of range for integer
  # values that bash can process (see OPSAPS-11583). So we check for any
  # value that is greater than 99 GB (length > 11) and then floor shmmax value
  # to 16 GB (as 8GB is max shared buffer value, 50% of shmmax)
  if [ ${#shmmax} -gt 11 ]; then
    shmmax=$SIXTEEN_GB
  fi

  if [ "$shmmax" -eq "$THIRTY_TWO_MB" ]; then
    let "shared_buffer=shmmax / 4"
    let "shared_buffer=shared_buffer / (8192 + 208)"
    echo "shared_buffers=$shared_buffer"
  elif [ "$shmmax" -gt "$THIRTY_TWO_MB" ]; then
    let "shared_buffer=shmmax / 2"
    if [ "$shared_buffer" -gt "$EIGHT_GB" ]; then
      shared_buffer=$EIGHT_GB
    fi

    let "quarter_of_ram=ram / 4"
    if [ "$shared_buffer" -gt "$quarter_of_ram" ]; then
      shared_buffer=$quarter_of_ram
    fi

    let "shared_buffer=shared_buffer / (8192 + 208)"
    echo "shared_buffers=$shared_buffer"
  fi
}

get_postgresql_major_version()
{
  local psql_output
  psql_output=$(psql --version)
  local regex
  regex="^psql \(PostgreSQL\) ([[:digit:]]+)\..*"

  if [[ $psql_output =~ $regex ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

get_standard_conforming_strings()
{
  local psql_version
  psql_version=$(get_postgresql_major_version)
  if [[ $psql_version -gt 8 ]]; then
    # These lines will be fed to sed, add \\ to make them look like single line to sed
    echo "# This is needed to make Hive work with Postgresql 9.1 and above\\"
    echo "# See OPSAPS-11795\\"
    echo "standard_conforming_strings=off"
  fi
}

backup_file()
{
  local FILE=$1
  if [[ -f $FILE ]] && [[ ! -f $FILE.$NOW ]]; then
    cp "$FILE" "$FILE"."$NOW"
  fi
}

configure_postgresql_conf()
{
  local CONF_FILE="$1"
  local IS_UPGRADE="$2"
  # Re-configure the listen address and port, since the postgresql-server
  # package may be using the default postgres port and listen address.
  # Though typically the default configs don't specify a
  # port, we try to remove it anyway.

  # Listen on all IP addresses, as monitoring services may reside on
  # different machines on the LAN.
  sed -e '/^listen_addresses\s*=/d' -i "$CONF_FILE"

  # Bump up max connections to server and shared buffer space that connections
  # need. shared_buffers should be at least 2 * max_connections.
  sed -e '/^max_connections\s*=/d' -i "$CONF_FILE"
  sed -e '/^shared_buffers\s*=/d' -i "$CONF_FILE"
  sed -e '/^standard_conforming_strings\s*=/d' -i "$CONF_FILE"

  # Prepend to the file
  local TMPFILE
  TMPFILE=$(mktemp /tmp/XXXXXXXX)

  if [ "$IS_UPGRADE" -eq 0 ]; then
    cat > "$TMPFILE" << EOF
#########################################
# === Generated by cloudera-scm-server-db at $NOW
#########################################
EOF
  fi

  cat "$CONF_FILE" >> "$TMPFILE"

  echo Adding configs
  sed -i "2a # === $CURRENT_VERSION_MARKER at $NOW" "$TMPFILE"
  sed -i "3a port = $DB_PORT" "$TMPFILE"
  sed -i "4a listen_addresses = '*'" "$TMPFILE"
  sed -i "5a max_connections = 500" "$TMPFILE"

  local LINE_NUM=6
  local SHARED_BUFFERS
  SHARED_BUFFERS="$(get_shared_buffers)"
  if [ -n "${SHARED_BUFFERS}" ]; then
    sed -i "${LINE_NUM}a ${SHARED_BUFFERS}" "$TMPFILE"
    LINE_NUM=7
  fi

  local SCS
  SCS="$(get_standard_conforming_strings)"
  if [ -n "${SCS}" ]; then
    sed -i "${LINE_NUM}a ${SCS}" "$TMPFILE"
  fi

  cat "$TMPFILE" > "$CONF_FILE"
}

wait_for_db_server_to_start()
{
  log "Wait for DB server to start"
  i=0
  until [ $i -ge 5 ]
  do
    i=$((i+1))
    sudo -u postgres psql -l && break
    sleep "${SLEEP_INTERVAL}"
  done
  if [ $i -ge 5 ]; then
    log "DB failed to start within $((i * SLEEP_INTERVAL)) seconds, exit with status 1"
    log "------- initialize-postgresql.sh failed -------"
    exit 1
  fi
}

log "------- initialize-postgresql.sh starting -------"

sudo service postgresql initdb
sudo service postgresql start
SCM_PWD=$(create_random_password)
DATA_DIR=/var/lib/pgsql/data
DB_HOST=$(hostname -f)
DB_PORT=${DB_PORT:-5432}
DB_HOSTPORT="$DB_HOST:$DB_PORT"
DB_PROP_FILE=/etc/cloudera-scm-server/db.properties
MGMT_DB_PROP_FILE=/etc/cloudera-scm-server/db.mgmt.properties

DB_LIST_FILE=$DATA_DIR/scm.db.list
NOW=$(date +%Y%m%d-%H%M%S)


configure_postgresql_conf $DATA_DIR/postgresql.conf 0

# Add header to pg_hba.conf.
echo "# Accept connections from all hosts" >> $DATA_DIR/pg_hba.conf


#echo "export LANGUAGE=en_US.UTF-8" >> ~/.bashrc
#echo "export LANG=en_US.UTF-8" >> ~/.bashrc
#echo "export LC_ALL=en_US.UTF-8" >> ~/.bashrc

#source ~/.bashrc


#put this line to the top of the ident to allow all local access
sed -i '/host.*127.*ident/i \
  host    all         all         127.0.0.1/32          md5  \ ' $DATA_DIR/pg_hba.conf
#append this line as well, need both to allow access
#echo "host    all         all         0.0.0.0/0          md5"

#echo "listen_addresses = '*'" >> $DATA_DIR/postgresql.conf

#configure the postgresql server to start at boot
sudo /sbin/chkconfig postgresql on
sudo service postgresql restart

wait_for_db_server_to_start

create_scm_db "$SCM_PWD"
create_mgmt_role_db ACTIVITYMONITOR amon
create_mgmt_role_db REPORTSMANAGER rman
create_mgmt_role_db NAVIGATOR nav
create_mgmt_role_db NAVIGATORMETASERVER navms
create_mgmt_role_db OOZIE oozie
create_hive_metastore
#host    oozie         oozie         0.0.0.0/0             md5
#create_mgmt_role_db HiveMetastoreServer navms
# with dynamic db creation, no need to call "create_mgmt_role_db" for new roles
# above calls kept for consistency

/usr/share/cmf/schema/scm_prepare_database.sh postgresql scm scm "$SCM_PWD" >> "${LOG_FILE}" 2>&1

configure_remote_connections

# restart to make sure all configuration take effects
sudo service postgresql restart

wait_for_db_server_to_start

log "------- initialize-postgresql.sh succeeded -------"

# always `exit 0` on success
exit 0
