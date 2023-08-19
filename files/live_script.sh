#!/bin/sh

LIVEUSER=live
PASSWORD=live
LIVEHOSTNAME=cruxlive

useradd -m -G users,wheel,audio,video -s /bin/bash $LIVEUSER
passwd -d $LIVEUSER &>/dev/null
passwd -d root &>/dev/null

echo "root:root" | chpasswd -c SHA512
echo "$LIVEUSER:$PASSWORD" | chpasswd -c SHA512

# hostname for live
echo $LIVEHOSTNAME > /etc/hostname
sed "s,HOSTNAME=.*,HOSTNAME=$LIVEHOSTNAME," -i /etc/rc.conf

# timezone
sed "s,TIMEZONE=.*,TIMEZONE=UTC," -i /etc/rc.conf

# services
for i in lo dbus alsa slim networkmanager; do
	[ -x /etc/rc.d/$i ] && sv="$sv $i"
done
sed "s,SERVICES=.*,SERVICES=($sv)," -i /etc/rc.conf

# live fstab
echo "# crux live fstab" > /etc/fstab
echo "devpts /dev/pts devpts noexec,nosuid,gid=tty,mode=0620 0 0" >> /etc/fstab
echo "shm /dev/shm tmpfs defaults 0 0" >> /etc/fstab

# slim autologin
if [ -f /etc/slim.conf ]; then
	echo "default_user $LIVEUSER" >> /etc/slim.conf
	echo "auto_login yes" >> /etc/slim.conf
fi

# enable sudo permission for all user in live
if [ -f /etc/sudoers ]; then
    echo "$LIVEUSER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# allow polkit for wheel group in live
if [ -d /etc/polkit-1 ]; then
    cat > /etc/polkit-1/rules.d/live.rules <<_EOF
polkit.addAdminRule(function(action, subject) {
    return ["unix-group:wheel"];
});
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
_EOF
fi

# run my custom trigger script
chmod +x /usr/bin/trigger
/usr/bin/trigger

# remove font config causing ugly font
rm -f /etc/fonts/conf.d/10-autohint.conf
