#!/usr/bin/env bash

set -e
set -u

export DBNAME="devsupplychainserver"
if [ $# -lt 1 ]; then
cat << eof
please enter a name of the test database ($DBNAME)
you can run:
./manage_db.sh $DBNAME
eof
    exit 1
fi

DBNAME=$1

psql \
    --echo-all \
    --set AUTOCOMMIT=off \
    --set ON_ERROR_STOP=on << EOF
DROP DATABASE IF EXISTS $DBNAME;
CREATE DATABASE $DBNAME;
EOF

psql_exit_status=$?
if [ $psql_exit_status != 0 ]; then
    echo "psql failed while trying to run this sql script" 1>&2
    exit $psql_exit_status
fi

echo "sql script successful"
exit 0
