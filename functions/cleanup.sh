#!/usr/bin/env bash

# Author:   Zhang Huangbin (zhb _at_ iredmail.org)

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

# Available variables for automate installation (value should be 'y' or 'n'):
#
#   AUTO_CLEANUP_REMOVE_SENDMAIL
#   AUTO_CLEANUP_REPLACE_FIREWALL_RULES
#   AUTO_CLEANUP_RESTART_FIREWALL
#   AUTO_CLEANUP_REPLACE_MYSQL_CONFIG
#
# Usage:
#   # AUTO_CLEANUP_REMOVE_SENDMAIL=y [...] bash iRedMail.sh

# -------------------------------------------
# Misc.
# -------------------------------------------
# Set cron file permission to 0600.
cleanup_set_cron_file_permission()
{
    for f in ${CRON_FILE_ROOT} ${CRON_FILE_AMAVISD} ${CRON_FILE_SOGO}; do
        if [ -f ${f} ]; then
            ECHO_DEBUG "Set file permission to 0600: ${f}."
            chmod 0600 ${f}
        fi
    done

    echo 'export status_cleanup_set_cron_file_permission="DONE"' >> ${STATUS_FILE}
}

cleanup_disable_selinux()
{
    if [ X"${DISTRO}" == X'RHEL' ]; then
        ECHO_INFO "Disable SELinux in /etc/selinux/config."
        [ -f /etc/selinux/config ] && perl -pi -e 's#^(SELINUX=)(.*)#${1}disabled#' /etc/selinux/config

        setenforce 0 >> ${INSTALL_LOG} 2>&1
    fi

    echo 'export status_cleanup_disable_selinux="DONE"' >> ${STATUS_FILE}
}

cleanup_remove_sendmail()
{
    # Remove sendmail.
    if [ X"${KERNEL_NAME}" == X'LINUX' ]; then
        eval ${LIST_ALL_PKGS} | grep '^sendmail' &>/dev/null

        if [ X"$?" == X"0" ]; then
            ECHO_QUESTION -n "Would you like to *REMOVE* sendmail now? [Y|n]"
            read_setting ${AUTO_CLEANUP_REMOVE_SENDMAIL}
            case ${ANSWER} in
                N|n )
                    ECHO_INFO "Disable sendmail, it is replaced by Postfix." && \
                    service_control disable sendmail
                    ;;
                Y|y|* )
                    eval ${remove_pkg} sendmail
                    ;;
            esac
        fi
    fi

    echo 'export status_cleanup_remove_sendmail="DONE"' >> ${STATUS_FILE}
}

cleanup_replace_firewall_rules()
{
    # Replace ssh numbers.
    if [ X"${SSHD_PORT2}" != X'22' ]; then
        # Append second ssh port number.
        perl -pi -e 's#(.*22.*)#${1}\n  <port protocol="tcp" port="$ENV{SSHD_PORT2}"/>#' ${SAMPLE_DIR}/firewall/firewalld/services/ssh.xml
        perl -pi -e 's#(.* 22 .*)#${1}\n-A INPUT -p tcp --dport $ENV{SSHD_PORT2} -j ACCEPT#' ${SAMPLE_DIR}/firewall/iptables/iptables.rules
        perl -pi -e 's#(.* 22 .*)#${1}\n-A INPUT -p tcp --dport $ENV{SSHD_PORT2} -j ACCEPT#' ${SAMPLE_DIR}/firewall/iptables/ip6tables.rules

        # Replace first ssh port number
        perl -pi -e 's#(.*)"22"(.*)#${1}"$ENV{SSHD_PORT}"${2}#' ${SAMPLE_DIR}/firewall/firewalld/services/ssh.xml
        perl -pi -e 's#(.*) 22 (.*)#${1} $ENV{SSHD_PORT} -j ACCEPT#' ${SAMPLE_DIR}/firewall/iptables/iptables.rules
        perl -pi -e 's#(.*) 22 (.*)#${1} $ENV{SSHD_PORT} -j ACCEPT#' ${SAMPLE_DIR}/firewall/iptables/ip6tables.rules
    fi

    perl -pi -e 's#(.*mail_services=.*)ssh(.*)#${1}$ENV{SSHD_PORTS_WITH_COMMA}${2}#' ${SAMPLE_DIR}/openbsd/pf.conf

    ECHO_QUESTION "Would you like to use firewall rules provided by iRedMail?"
    ECHO_QUESTION -n "File: ${FIREWALL_RULE_CONF}, with SSHD ports: ${SSHD_PORTS_WITH_COMMA}. [Y|n]"
    read_setting ${AUTO_CLEANUP_REPLACE_FIREWALL_RULES}
    case ${ANSWER} in
        N|n ) ECHO_INFO "Skip firewall rules." ;;
        Y|y|* )
            backup_file ${FIREWALL_RULE_CONF}
            if [ X"${KERNEL_NAME}" == X'LINUX' ]; then
                ECHO_INFO "Copy firewall sample rules."

                if [ X"${USE_FIREWALLD}" == X'YES' ]; then
                    cp -f ${SAMPLE_DIR}/firewall/firewalld/zones/iredmail.xml ${FIREWALL_RULE_CONF}
                    perl -pi -e 's#^(DefaultZone=).*#${1}iredmail#g' ${FIREWALLD_CONF}

                    cp -f ${SAMPLE_DIR}/firewall/firewalld/services/ssh.xml ${FIREWALLD_CONF_DIR}/services/

                    if [ X"${DISTRO}" == X'RHEL' ]; then
                        cd ${ETC_SYSCONFIG_DIR}/network-scripts/
                        if ls | grep -E '[0-9a-zA-Z]' &>/dev/null; then
                            perl -pi -e 's#ZONE=public#ZONE=iredmail#g' *
                        fi
                    fi

                    service_control enable firewalld

                elif [ X"${USE_NFTABLES}" == X'YES' ]; then
                    cp -f ${SAMPLE_DIR}/firewall/nftables.conf ${NFTABLES_CONF}

                    perl -pi -e 's#(.*) 80 (.*)#${1} $ENV{PORT_HTTP} ${2}#' ${NFTABLES_CONF}
                    if [ X"${SSHD_PORT}" == X"${SSHD_PORT2}" ]; then
                        perl -pi -e 's#(.*) 22 (.*)#${1} $ENV{SSHD_PORT} ${2}#' ${NFTABLES_CONF}
                    elif [ X"${SSHD_PORT}" != X'' -a X"${SSHD_PORT2}" != X'' -a X"${SSHD_PORT}" != X"${SSHD_PORT2}" ]; then
                        perl -pi -e 's#(.*) 22 (.*)#${1} {$ENV{SSHD_PORTS_WITH_COMMA}} ${2}#' ${NFTABLES_CONF}
                    fi

                    service_control enable nftables
                else
                    cp -f ${SAMPLE_DIR}/firewall/iptables/iptables.rules ${FIREWALL_RULE_CONF}
                    cp -f ${SAMPLE_DIR}/firewall/iptables/ip6tables.rules ${FIREWALL_RULE_CONF6}

                    service_control enable iptables
                    service_control enable ip6tables
                fi

                # Replace HTTP port.
                [ X"${PORT_HTTP}" != X"80" ]&& \
                    perl -pi -e 's#(.*)80(,.*)#${1}$ENV{PORT_HTTP}${2}#' ${FIREWALL_RULE_CONF}

            elif [ X"${KERNEL_NAME}" == X'OPENBSD' ]; then
                # Enable pf
                service_control enable pf

                # Whitelist file required by spamd(8)
                touch /etc/mail/nospamd

                ECHO_INFO "Copy firewall sample rules: ${FIREWALL_RULE_CONF}."
                cp -f ${SAMPLE_DIR}/openbsd/pf.conf ${FIREWALL_RULE_CONF}
            fi

            # Prompt to restart iptables.
            ECHO_QUESTION -n "Restart firewall now (with ssh ports: ${SSHD_PORTS_WITH_COMMA})? [y|N]"
            read_setting ${AUTO_CLEANUP_RESTART_FIREWALL}
            case ${ANSWER} in
                Y|y )
                    ECHO_INFO "Restarting firewall ..."

                    if [ X"${DISTRO}" == X'OPENBSD' ]; then
                        /sbin/pfctl -ef ${FIREWALL_RULE_CONF} >> ${INSTALL_LOG} 2>&1
                    else
                        if [ X"${USE_FIREWALLD}" == X'YES' ]; then
                            firewall-cmd --complete-reload >> ${INSTALL_LOG} 2>&1
                        elif [ X"${USE_NFTABLES}" == X'YES' ]; then
                            service_control restart nftables
                        else
                            service_control restart iptables
                            service_control restart ip6tables
                        fi
                    fi
                    ;;
                *) : ;;
            esac
    esac

    echo 'export status_cleanup_replace_firewall_rules="DONE"' >> ${STATUS_FILE}
}

cleanup_replace_mysql_config()
{
    if [[ X"${DISTRO}" == X'RHEL' ]]; then
        if [ X"${BACKEND}" == X'MYSQL' -o X"${BACKEND}" == X'OPENLDAP' ]; then
            # Both MySQL and OpenLDAP backend need MySQL database server, so prompt
            # this config file replacement.
            ECHO_QUESTION "Would you like to use MySQL configuration file shipped within iRedMail now?"
            ECHO_QUESTION -n "File: ${MYSQL_MY_CNF}. [Y|n]"
            read_setting ${AUTO_CLEANUP_REPLACE_MYSQL_CONFIG}
            case ${ANSWER} in
                N|n ) ECHO_INFO "Skip copy and modify MySQL config file." ;;
                Y|y|* )
                    backup_file ${MYSQL_MY_CNF}
                    ECHO_INFO "Copy MySQL sample file: ${MYSQL_MY_CNF}."
                    cp -f ${SAMPLE_DIR}/mysql/my.cnf ${MYSQL_MY_CNF}
                    ;;
            esac
        fi
    fi

    echo 'export status_cleanup_replace_mysql_config="DONE"' >> ${STATUS_FILE}
}

cleanup_update_compile_spamassassin_rules()
{
    # Required on FreeBSD to start Amavisd-new.
    ECHO_INFO "Updating SpamAssassin rules (sa-update), please wait ..."
    ${BIN_SA_UPDATE} >> ${INSTALL_LOG} 2>&1

    ECHO_INFO "Compiling SpamAssassin rulesets (sa-compile), please wait ..."
    ${BIN_SA_COMPILE} >> ${INSTALL_LOG} 2>&1

    echo 'export status_cleanup_update_compile_spamassassin_rules="DONE"' >> ${STATUS_FILE}
}

cleanup_update_clamav_signatures()
{
    # Update clamav before start clamav-clamd service.
#    if [ X"${FRESHCLAM_UPDATE_IMMEDIATELY}" == X'YES' ]; then
#        ECHO_INFO "Updating ClamAV database (freshclam), please wait ..."
#        freshclam 2>/dev/null | grep -v 'locked by another process'
#    fi

    echo 'export status_cleanup_update_clamav_signatures="DONE"' >> ${STATUS_FILE}
}

cleanup_feedback()
{
    # Send package names to iRedMail project to help developers
    # understand which are most important to users.
    url="iredmail_version=${PROG_VERSION}&backend=${BACKEND_ORIG}"

    # Hardware.
    url="${url}&arch=${OS_ARCH}"
    url="${url}&distro=${DISTRO}-${DISTRO_CODENAME}-${DISTRO_VERSION}"

    # Packages.
    pkgs=""
    [ X"${USE_ROUNDCUBE}" == X'YES' ]   && pkgs="${pkgs},roundcube"
    [ X"${USE_SOGO}" == X'YES' ]        && pkgs="${pkgs},sogo"
    [ X"${USE_NETDATA}" == X'YES' ]     && pkgs="${pkgs},netdata"
    [ X"${USE_FAIL2BAN}" == X'YES' ]    && pkgs="${pkgs},fail2ban"
    [ X"${USE_IREDADMIN}" == X'YES' ]   && pkgs="${pkgs},iredadmin"
    [ X"${WEB_SERVER}" == X'NGINX' ]    && pkgs="${pkgs},nginx"
    url="${url}&pkgs=${pkgs}"

    cd /tmp
    ${FETCH_CMD} "https://l.iredmail.org/iredmail/pkgs?${url}" &>/dev/null
    rm -f /tmp/pkgs* &>/dev/null

    echo 'export status_cleanup_feedback="DONE"' >> ${STATUS_FILE}
}

cleanup()
{
    # Store iRedMail version number in /etc/iredmail-release
    cat > /etc/${PROG_NAME_LOWERCASE}-release <<EOF
${PROG_VERSION} ${BACKEND_ORIG} edition.
# Get professional support from iRedMail Team: http://www.iredmail.org/support.html
EOF

    cat <<EOF

*************************************************************************
* ${PROG_NAME}-${PROG_VERSION} installation and configuration complete.
*************************************************************************

EOF

    # Mail installation related info to postmaster@
    msg_date="$(date "+%a, %d %b %Y %H:%M:%S %z")"

    ECHO_DEBUG "Mail sensitive administration info to ${DOMAIN_ADMIN_EMAIL}."
    FILE_IREDMAIL_INSTALLATION_DETAILS="${DOMAIN_ADMIN_MAILDIR_INBOX}/details.eml"
    FILE_IREDMAIL_LINKS="${DOMAIN_ADMIN_MAILDIR_INBOX}/links.eml"
    FILE_IREDMAIL_MUA_SETTINGS="${DOMAIN_ADMIN_MAILDIR_INBOX}/mua.eml"

    cat > ${FILE_IREDMAIL_INSTALLATION_DETAILS} <<EOF
From: root@${HOSTNAME}
To: ${DOMAIN_ADMIN_EMAIL}
Date: ${msg_date}
Subject: Details of this iRedMail installation

$(cat ${TIP_FILE})
EOF

    cat > ${FILE_IREDMAIL_LINKS} <<EOF
From: root@${HOSTNAME}
To: ${DOMAIN_ADMIN_EMAIL}
Date: ${msg_date}
Subject: Useful resources for iRedMail administrator

$(cat ${DOC_FILE})
EOF

    cat > ${FILE_IREDMAIL_MUA_SETTINGS} <<EOF
From: root@${HOSTNAME}
To: ${DOMAIN_ADMIN_EMAIL}
Date: ${msg_date}
Subject: How to configure your mail client applications (MUA)


* POP3 service: port 110 over STARTTLS (recommended), or port 995 with SSL.
* IMAP service: port 143 over STARTTLS (recommended), or port 993 with SSL.
* SMTP service: port 587 over STARTTLS.
  If you need to support old mail clients with SMTP over SSL (port 465),
  please check our tutorial: https://docs.iredmail.org/enable.smtps.html
* CalDAV and CardDAV server addresses: https://<server>/SOGo/dav/<full email address>

For more details, please check detailed documentations:
https://docs.iredmail.org/#mua
EOF

    for f in ${FILE_IREDMAIL_INSTALLATION_DETAILS} \
        ${FILE_IREDMAIL_LINKS} \
        ${FILE_IREDMAIL_MUA_SETTINGS}; do
        chown -R ${SYS_USER_VMAIL}:${SYS_GROUP_VMAIL} ${f}
        chmod -R 0700 ${f}
    done

    check_status_before_run cleanup_set_cron_file_permission
    check_status_before_run cleanup_disable_selinux
    check_status_before_run cleanup_remove_sendmail

    [ X"${KERNEL_NAME}" == X'LINUX' -o X"${KERNEL_NAME}" == X'OPENBSD' ] && \
        check_status_before_run cleanup_replace_firewall_rules

    check_status_before_run cleanup_replace_mysql_config

    if [ X"${DISTRO}" == X'FREEBSD' -o X"${DISTRO}" == X'OPENBSD' ]; then
        check_status_before_run cleanup_update_compile_spamassassin_rules
    fi

    check_status_before_run cleanup_update_clamav_signatures
    check_status_before_run cleanup_feedback

    cat <<EOF
********************************************************************
* URLs of installed web applications:
*
EOF

    if [ X"${USE_ROUNDCUBE}" == X'YES' ]; then
        cat <<EOF
* - Roundcube webmail: https://${HOSTNAME}/mail/
EOF
    fi

    if [ X"${USE_SOGO}" == X'YES' ]; then
        cat <<EOF
* - SOGo groupware: https://${HOSTNAME}/SOGo/
EOF
    fi

    if [ X"${USE_NETDATA}" == X'YES' ]; then
        cat <<EOF
* - netdata (monitor): https://${HOSTNAME}/netdata/
EOF
    fi
    cat <<EOF
*
* - Web admin panel (iRedAdmin): https://${HOSTNAME}/iredadmin/
*
* You can login to above links with below credential:
*
* - Username: ${DOMAIN_ADMIN_EMAIL}
* - Password: ${DOMAIN_ADMIN_PASSWD_PLAIN}
*
*
********************************************************************
* Congratulations, mail server setup completed successfully. Please
* read below file for more information:
*
*   - ${TIP_FILE}
*
* And it's sent to your mail account ${DOMAIN_ADMIN_EMAIL}.
*
********************* WARNING **************************************
*
* Please reboot your system to enable all mail services.
*
********************************************************************
EOF

    echo 'export status_cleanup="DONE"' >> ${STATUS_FILE}
}
