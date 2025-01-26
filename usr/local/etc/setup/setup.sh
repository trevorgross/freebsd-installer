#!/bin/sh

# disable sendmail, add a user, optionally install more software
# I don't really know if all the sendmail disabling is still
# necessary as of 14.0, but on 13.2 it would delay the boot process
# until this was disabled.

cd /usr/local/etc/setup

# avoid errors about failing post-install scripts
pkg install -y indexinfo
[ -z $(echo $PATH | tr ':' '\n' | grep -x /usr/local/bin) ] && export PATH=$PATH:/usr/local/bin

rcsetup() {

    RCFILE=/etc/rc.conf

    cat <<RCCONF >> "$RCFILE"
# START disable sendmail
# https://gist.github.com/igalic/c77ed494e102977c9fd06ce9b053cda0
# since sendmail_enable="NONE" is deprecated (since 2004, lol), this is how to disable all of Sendmail:
sendmail_enable="NO"
sendmail_submit_enable="NO"
sendmail_msp_queue_enable="NO"
sendmail_outbound_enable="NO"

# don't allow cron to mail
cron_flags="-m ''"
# END disable sendmail

RCCONF

}

mailersetup() {

    MAILFILE=/etc/mail/mailer.conf

    sed -i -e 's/^#*/#/' "$MAILFILE"

    cat <<MAILER >> "$MAILFILE"

# https://gist.github.com/igalic/c77ed494e102977c9fd06ce9b053cda0
sendmail        /usr/bin/true
mailq           /usr/bin/true
newaliases      /usr/bin/true
hoststat        /usr/bin/true
purgestat       /usr/bin/true
MAILER

}

periodicsetup() {

    PERIODICFILE=/etc/periodic.conf

    cat <<PERIODIC > "$PERIODICFILE"
# https://gist.github.com/igalic/c77ed494e102977c9fd06ce9b053cda0

# disable sendmail (mailqueue) cleanups:
daily_clean_hoststat_enable="NO"
daily_status_mail_rejects_enable="NO"
daily_status_mailq_enable="NO"
daily_submit_queuerun="NO"

# disable periodic's emailing by logging!
daily_output=/var/log/daily.log
weekly_output=/var/log/weekly.log
monthly_output=/var/log/monthly.log

# put these into the log, instead of trying to mail them:
daily_status_security_inline="YES"
weekly_status_security_inline="YES"
monthly_status_security_inline="YES"
PERIODIC

}

usersetup() {
    pkg install -y zsh sudo
    echo "ii::::::::/usr/local/bin/zsh:asdf" > /tmp/user
    adduser -f /tmp/user
    pw groupmod wheel -M ii
    rm /tmp/user
    cat <<ZSHRC > /home/ii/.zshrc
export HISTFILE=~/.zsh_history
export HISTFILESIZE=10000000
export HISTSIZE=10000000
export PROMPT="%~ %# "
export SAVEHIST=10000
setopt HIST_IGNORE_ALL_DUPS
ZSHRC
    mkdir /home/ii/.ssh && chmod 700 /home/ii/.ssh
    echo "SOME_SSH_PUBLIC_KEY_SO_YOU_CAN_SSH_IN_WITH_NO_PASSWORD" > /home/ii/.ssh/authorized_keys
    chmod 600 /home/ii/.ssh/authorized_keys
    chown -R ii:ii /home/ii
    echo "ii ALL=(ALL) NOPASSWD: /sbin/poweroff" > /usr/local/etc/sudoers.d/99-allow-poweroff
    chmod 440 /usr/local/etc/sudoers.d/99-allow-poweroff
}

agentsetup() {
    pkg install -y qemu-guest-agent
    
    # add service to startup
    echo '# Enabled for qemu guest agent:' >> /etc/rc.conf
    echo '# qemu_guest_agent_enable="YES"' >> /etc/rc.conf
    echo '' >> /etc/rc.conf
    sysrc qemu_guest_agent_enable="YES"
}

guacsetup() {
    if [ -f install_guacamole.sh ]; then
        chmod 755 install_guacamole.sh
        # ./install_guacamole.sh
        # for TOTP
        ./install_guacamole.sh TOTP
    else
        echo "Guacamole install script not found, skipping."
    fi
}

wikisetup() {
    if [ -f install_mediawiki.sh ]; then
        chmod 755 install_mediawiki.sh
        ./install_mediawiki.sh
    else
        echo "Mediawiki install script not found, skipping."
    fi
}

unifisetup() {
    pkg install -y unifi8

    # add service to startup
    echo '# Enabled for Unifi controller:' >> /etc/rc.conf
    echo '# unifi_enable="YES"' >> /etc/rc.conf
    sysrc unifi_enable="YES"
    cat <<UNIFISETUP >> /root/unifi-setup
Unifi setup completed on: $(date +%c).
Access controller at https://<ip>:8443
UNIFISETUP
}

sethost() {
    sysrc "hostname=$1"
}

rcsetup

mailersetup

periodicsetup

usersetup

agentsetup

case "$1" in
    'base')
        sethost freebsd
        ;;
    'guac')
        guacsetup
        sethost guac
        ;;
    'unifi')
        unifisetup
        sethost unifi
        ;;
    'wiki')
        wikisetup
        sethost wiki
        ;;
esac

