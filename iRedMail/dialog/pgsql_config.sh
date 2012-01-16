#!/usr/bin/env bash

# Author:   Zhang Huangbin <zhb(at)iredmail.org>

#---------------------------------------------------------------------
# This file is part of iRedMail, which is an open source mail server
# solution for Red Hat(R) Enterprise Linux, CentOS, Debian and Ubuntu.
#
# iRedMail is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# iRedMail is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with iRedMail.  If not, see <http://www.gnu.org/licenses/>.
#---------------------------------------------------------------------

# --------------------------------------------------
# --------------------- MySQL ----------------------
# --------------------------------------------------

. ${CONF_DIR}/postgresql

# Root password.
while : ; do
    ${DIALOG} \
    --title "Password for PostgreSQL administrator: ${PGSQL_ROOT_USER}" \
    ${PASSWORDBOX} "\
Please specify password for PostgreSQL administrator: ${PGSQL_ROOT_USER}

WARNING:

    * EMPTY password is *NOT* permitted.
" 20 76 2>/tmp/pgsql_rootpw

    PGSQL_ROOT_PASSWD="$(cat /tmp/pgsql_rootpw)"
    [ X"${PGSQL_ROOT_PASSWD}" != X"" ] && break
done

echo "export PGSQL_ROOT_PASSWD='${PGSQL_ROOT_PASSWD}'" >>${CONFIG_FILE}
rm -f /tmp/pgsql_rootpw
