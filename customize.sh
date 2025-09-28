#!/sbin/sh

set_perm_recursive $MODPATH 0 0 0755 0644
set_perm_recursive $MODPATH/scripts 0 0 0755 0644
set_perm  $MODPATH/service.sh    0  0  0755
set_perm  $MODPATH/scripts/start.sh    0  0  0755
