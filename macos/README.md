STAFF MAC SETUP — quick reference
=================================


ON each staff Mac:
  1. open term
  2. Staff accounts are non-admin, so switch to the machine's admin
     account for sudo:
       su <adminaccount>
       sudo bash /Volumes/<STAFFKIT>/mac/setup.sh
     When the script asks "Staff user account to configure", make sure
     it shows the STAFF username ---- EVENTUALLY GOING TO MAKE USER NAME FIRSTINITIAL.LASTNAME!!! 
  3. Pick options from the menu
  4. RustDesk - MAKE SURE YOU GIVE REMOTE ACCESS !@#!@#
  5. Check the summary + status output; the log is saved to mac/logs/
     on the USB, named per machine.
  6. The Chrome step also saves each profile's bookmarks to
     mac/backups/ on the USB

AFTER the round:
  - Wazuh dashboard: all hosts Active
  - Fleet: all hosts enrolled, profiles verified
  - Google Admin -> Managed browsers: all machines listed
  - Keep or wipe the USB — config.env holds enrollment secrets.
