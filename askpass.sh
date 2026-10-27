#!/bin/sh
# Password prompt for "sudo -A" when there is no terminal (see setup.sh).
/usr/bin/osascript -e 'display dialog "Homelab setup needs your password for sudo:" default answer "" with hidden answer with title "Homelab setup"' -e 'text returned of result'
