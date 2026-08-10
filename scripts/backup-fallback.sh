#!/bin/bash
# File              : osxbackup-fallback.sh
# Date              : 26.02.2022
# Last Modified Date: 27.02.2022
# Last Modified By  : blujai831 <benjamin.i.mccann@gmail.com>

# This is an alternative version of osxbackup.sh
# that does only what was asked and has no additional features.
# If a bug is found in osxbackup.sh,
# it will probably be absent from osxbackup-fallback.sh.

# Show usage on request.
if [[ "$*" == --help || ! "$*" ]]; then
    cat << EOT
USAGE: $0 [DIRS ...] DEST
EXAMPLE: $0 ${USER}@${USER}s-other-pc:/Users/$USER
EOT
    cat << 'EOT'
Archives $HOME/{Documents,Desktop}
to /Users/Shared/$USER-$(date +'%F-%H-%M-%S'),
scp's the archive to DEST,
and deletes the local copy of the archive on success.
If DIRS are given, uses them instead of $HOME/{Documents,Desktop}.
EOT
    exit
fi

# Otherwise, create archive, transmit, and delete on success.

backup="/Users/Shared/$USER-$(date +'%F-%H-%M-%S').gzip"
dirs=("${@:1:$(($#-1))}") # get leading args
if (( ! "${#dirs[@]}" )); then
    dirs=("$HOME"/{Documents,Desktop}) # default leading args
fi
dest="${@:$#}" # get trailing arg

tar -cvzf "$backup" "${dirs[@]}" &&
scp -v "$backup" "$dest" &&
rm -fv "$backup"
