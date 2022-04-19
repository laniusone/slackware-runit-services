#!/bin/bash
#
# rc.M		This file is executed by init(8) when the system is being
#		initialized for one of the "multi user" run levels (i.e.
#		levels 1 through 6).  It usually does mounting of file
#		systems et al.
#
# Version:	@(#)/etc/rc.d/rc.M  15.0  Fri Nov 12 18:51:28 UTC 2021
#
# Author:	Fred N. van Kempen, <waltje@uwalt.nl.mugnet.org>
#		Heavily modified by Patrick Volkerding <volkerdi@slackware.com>
#

# Tell the viewers what's going to happen.
echo "Going multiuser..."

# If we are in an lxc container, set $container to skip parts of the script.
# Thanks to Matteo Bernardini <ponce@slackbuilds.org> and Chris Willing for
# the initial work making this script lxc compatible.
if grep -aq container=lxc /proc/1/environ 2> /dev/null ; then
  container="lxc"
fi

# Update all the shared library links:
if [ -x /sbin/ldconfig ]; then
  echo "Updating shared library links:  /sbin/ldconfig &"
  /sbin/ldconfig &
fi

# Call the setterm init script to set screen blanking and power management
# defaults:
if [ -x /etc/rc.d/rc.setterm -a -z "$container" ]; then
  /etc/rc.d/rc.setterm
fi

# Set the hostname:
if [ -z "$container" ]; then
  if [ -r /etc/HOSTNAME ]; then
    /bin/hostname $(cat /etc/HOSTNAME)
  else
    # fall back on this old default:
    echo "darkstar.example.net" > /etc/HOSTNAME
    /bin/hostname $(cat /etc/HOSTNAME)
  fi
fi

# Set the permissions on /var/log/dmesg according to whether the kernel
# permits non-root users to access kernel dmesg information:
if [ -r /proc/sys/kernel/dmesg_restrict ]; then
  if [ $(cat /proc/sys/kernel/dmesg_restrict) = 1 ]; then
    touch /var/log/dmesg
    chmod 640 /var/log/dmesg
  fi
else
  touch /var/log/dmesg
  chmod 644 /var/log/dmesg
fi
# Save the contents of 'dmesg':
/bin/dmesg -s 65536 > /var/log/dmesg

# Update the X font indexes:
if [ -x /usr/bin/fc-cache ]; then
  echo "Updating X font indexes:  /usr/bin/fc-cache -f &"
  /usr/bin/fc-cache -f &
fi

# Run rc.udev again.  This will start udev if it is not already running
# (for example, upon return from runlevel 1), otherwise it will trigger it
# to look for device changes and to generate persistent rules if needed.
if grep -wq sysfs /proc/mounts && grep -q devtmpfs /proc/filesystems ; then
  if ! grep -wq nohotplug /proc/cmdline ; then
    if [ -x /etc/rc.d/rc.udev -a -z "$container" ]; then
      /etc/rc.d/rc.udev start
    fi
  fi
fi

# Initialize the networking hardware.
if [ -x /etc/rc.d/rc.inet1 ]; then
  /etc/rc.d/rc.inet1
fi

# Mount any additional filesystem types that haven't already been mounted:
mount -a -v 2> /dev/null | grep -v -e "already mounted" -e "ignored" | cut -f 1 -d : | tr -d ' ' | while read dev ; do mount | grep "${dev} " ; done

# Remove stale locks and junk files (must be done after mount -a!)
/bin/rm -f /var/lock/* /var/spool/uucp/LCK..* /tmp/.X*lock /tmp/.X11-unix/* 2> /dev/null

# Remove stale hunt sockets so the game can start.
if [ -r /tmp/hunt -o -r /tmp/hunt.stats ]; then
  echo "Removing your stale hunt sockets from /tmp."
  /bin/rm -f /tmp/hunt*
fi

# Ensure basic filesystem permissions sanity.
chmod 755 / 2> /dev/null
chmod 1777 /tmp /var/tmp

# Enable CPU frequency scaling:
if [ -x /etc/rc.d/rc.cpufreq -a -z "$container" ]; then
  /etc/rc.d/rc.cpufreq start
fi

# Update any existing icon cache files:
if find /usr/share/icons -maxdepth 2 2> /dev/null | grep -q icon-theme.cache ; then
  for theme_dir in /usr/share/icons/* ; do
    if [ -r ${theme_dir}/icon-theme.cache ]; then
      echo "Updating icon-theme.cache in ${theme_dir}..."
      /usr/bin/gtk-update-icon-cache -t -f ${theme_dir} 1> /dev/null 2> /dev/null &
    fi
  done
  # This would be a large file and probably shouldn't be there.
  if [ -r /usr/share/icons/icon-theme.cache ]; then
    echo "Deleting icon-theme.cache in /usr/share/icons..."
    #/usr/bin/gtk-update-icon-cache -t -f /usr/share/icons 1> /dev/null 2> /dev/null &
    rm -f /usr/share/icons/icon-theme.cache
  fi
fi

# Update mime database:
if [ -x /usr/bin/update-mime-database -a -d /usr/share/mime ]; then
  echo "Updating MIME database:  /usr/bin/update-mime-database /usr/share/mime &"
  /usr/bin/update-mime-database /usr/share/mime 1> /dev/null 2> /dev/null &
fi

# These GTK+/pango files need to be kept up to date for
# proper input method, pixbuf loaders, and font support.
if [ -x /usr/bin/update-gtk-immodules ]; then
  echo "Updating gtk.immodules:"
  echo "  /usr/bin/update-gtk-immodules &"
  /usr/bin/update-gtk-immodules > /dev/null 2>&1 &
fi
if [ -x /usr/bin/update-gdk-pixbuf-loaders ]; then
  echo "Updating gdk-pixbuf.loaders:"
  echo "  /usr/bin/update-gdk-pixbuf-loaders &"
  HOME=/root /usr/bin/update-gdk-pixbuf-loaders > /dev/null 2>&1 &
fi
if [ -x /usr/bin/update-pango-querymodules ]; then
  echo "Updating pango.modules:"
  echo "  /usr/bin/update-pango-querymodules &"
  /usr/bin/update-pango-querymodules > /dev/null 2>&1 &
fi
if [ -x /usr/bin/glib-compile-schemas ]; then
  echo "Compiling GSettings XML schema files:"
  echo "  /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas &"
  /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas >/dev/null 2>&1 &
fi

# Turn on process accounting.  To enable process accounting, make sure the
# option for BSD process accounting is enabled in your kernel, and then
# create the file /var/log/pacct (touch /var/log/pacct).  By default, process
# accounting is not enabled (since /var/log/pacct does not exist).  This is
# because the log file can get VERY large.
if [ -x /sbin/accton -a -r /var/log/pacct ]; then
  chmod 640 /var/log/pacct
  /sbin/accton /var/log/pacct
fi

# Slackware-Mini-Quota-HOWTO:
# To really activate quotas, you'll need to add 'usrquota' and/or 'grpquota' to
# the appropriate partitions as listed in /etc/fstab.  Here's an example:
#
# /dev/hda2      /home      ext3     defaults,usrquota      1   1
#
# You'll then need to setup initial quota files at the top of the partitions
# to support quota, like this:
# touch /home/aquota.user /home/aquota.group
# chmod 600 /home/aquota.user /home/aquota.group
#
# Then, reboot to activate the system.
# To edit user quotas, use 'edquota'.  See 'man edquota'.  Also, the
# official Quota Mini-HOWTO has lots of useful information.  That can be found
# here:  /usr/doc/Linux-HOWTOs/Quota

# Check quotas and then turn quota system on:
if grep -q quota /etc/fstab ; then
  for quotafs in $(awk '/quota/ {print $2}' /etc/fstab) ; do
    /bin/rm -f $quotafs/{a,}quota.{group,user}.new
  done
  if [ -x /sbin/quotacheck ]; then
    echo "Checking filesystem quotas:  /sbin/quotacheck -avugm"
    /sbin/quotacheck -avugm
  fi
  if [ -x /sbin/quotaon ]; then
    echo "Activating filesystem quotas:  /sbin/quotaon -avug"
    /sbin/quotaon -avug
  fi
fi

# Load a custom screen font if the user has an rc.font script.
if [ -x /etc/rc.d/rc.font ]; then
  /etc/rc.d/rc.font
fi

# Load a custom keymap if the user has an rc.keymap script.
if [ -x /etc/rc.d/rc.keymap ]; then
  /etc/rc.d/rc.keymap
fi

# Start the local setup procedure.
if [ -x /etc/rc.d/rc.local ]; then
  /etc/rc.d/rc.local
fi

# All done.
