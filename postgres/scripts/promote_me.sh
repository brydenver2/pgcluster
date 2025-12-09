#!/bin/bash

PGVER=${PGVER:-17}
/usr/lib/postgresql/${PGVER}/bin/repmgr --log-to-file -f /etc/repmgr/${PGVER}/repmgr.conf standby promote -v
exit $?
