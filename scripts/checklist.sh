#!/bin/bash
# File              : checklist.sh
# Date              : 26.02.2022
# Last Modified Date: 11.03.2022
# Last Modified By  : blujai831 <benjamin.i.mccann@gmail.com>

# =====
# Usage
# =====

usage() { cat << EOT
Usage: $0
    [-h] [-i KEY] [-p PORT] [-n INBOX]
    [OSXBACKUP_ARG ...] [FILE|REMOTE] [< FILE]

Backs up a single REMOTE or a list of REMOTEs in a FILE.

Options -h, -i, -p, and -n must be given in the order shown,
and must precede all OSXBACKUP_ARGs, but any may be omitted.
-h indicates to show this message.
-i and -p are used to connect to REMOTEs.
-n (default /mnt/shared/backups) sets download directory
for backups received from REMOTEs.

If OSXBACKUP_ARGs are given, they are forwarded to osxbackup.sh.
osxbackup.sh must be in the same directory as checklist.sh.

The FILE should contain one REMOTE per line,
which may have up to 2 |-separated NAMEs.
(There may be further |-separated fields, but they are ignored.)
EOT
}

# ===========
# Definitions
# ===========

# $CHECKLIST_SH_DEFS_ONLY
# Set this variable to skip running anything except definitions
# (and the EXIT trap).
CHECKLIST_SH_DEFS_ONLY="${CHECKLIST_SH_DEFS_ONLY:-}"

# $rundir
# Script temp directory. Initialized by mkrundir.
rundir=''

# ${atexit[@]}
# List of functions to call on exit.
atexit=()
trap 'for fun in "${atexit[@]}"; do "$fun"; done' EXIT

# atexit COMMAND ...
# Prepends to ${atexit[@]}.
atexit() {
    atexit=("$@" "${atexit[@]}")
}

# delay-write FILE
# Reads all of stdin and writes it to FILE.
# Does not open FILE for writing until all of stdin is read.
delay-write() {
    mkrundir
    cat > "$rundir/delay-write.data"
    cat "$rundir/delay-write.data" > "$*"
}

# rmrundir
# If $rundir exists, random-out all its contents and delete it.
rmrundir() {
    if [[ -d "$rundir" ]]; then
        # Random-out all files in the directory
        local file; while read file; do
            local wc_output=($(wc -c "$file")) # word-splitting on purpose
            head -c"$wc_output" /dev/urandom | delay-write "$file"
        done < <(find "$rundir" -type f)
        # Delete the directory
        rm -rf "$rundir"
    fi
}

# mkrundir
# Creates a temp directory and guarantees it will be deleted at exit.
# Stores the filename in global variable rundir.
# Safe to call multiple times; if it has already been called,
# it will have no effect.
mkrundir() {
    # Check if we already have a rundir, only create it if we don't
    if [[ ! ( "$rundir" || -d "$rundir" ) ]]; then
        # Ensure the directory will be deleted
        atexit rmrundir
        # Create the directory
        # (the umask doesn't escape the captured subshell)
        rundir=`
            `"$(umask 0077; mktemp -d "${TMPDIR:-/tmp}/$0.d.XXXXXX")"
    fi
}

# rmreplykey
# Revokes authorization for $rundir/replykey.pub if it exists.
# Does not actually delete $rundir/reply-key; leaves that to rmrundir.
rmreplykey() {
    local keyfile="$rundir/replykey.pub"
    local authfile="$HOME/.ssh/authorized_keys"
    if [[ -f "$keyfile" && -f "$authfile" ]]; then
        grep -Fvf "$keyfile" "$authfile" | delay-write "$authfile"
    fi
}

# mkreplykey
# Creates and authorizes a non-passphrase-protected RSA key pair in $rundir.
# The filenames will be $rundir/replykey{,.pub}.
mkreplykey() {
    # Ensure rundir exists
    mkrundir
    # Ensure authorization for the key will be revoked
    atexit rmreplykey
    # Create and authorize key
    ssh-keygen -f "$rundir/replykey" -t rsa -N ''
    cat "$rundir/replykey.pub" >> "$HOME/.ssh/authorized_keys"
}

# ssh-with-reply ARG ... < SCRIPT
# Generates a reply key, forms an SSH connection according to ARGs,
# sends this script (checklist.sh) over the SSH connection
# with CHECKLIST_SH_DEFS_ONLY enabled, uses the functions in this script
# to store the reply key on the remote host, and remotely executes SCRIPT.
# In SCRIPT, to form a reply connection, you can use \$rundir/replykey
# as the key file and \$replyaddr as the reply address.
ssh-with-reply() { ssh "$@" bash -s << EOT
    # Import definitions from this script
    CHECKLIST_SH_DEFS_ONLY=:
    $(cat "$BASH_SOURCE")
    # Receive key from initiating machine
    mkrundir
    cat > "\$rundir/replykey" <<< "$(cat "$rundir/replykey")"
    cat > "\$rundir/replykey.pub" <<< "$(cat "$rundir/replykey.pub")"
    chmod 0600 "\$rundir/replykey"
    # Init vars to facilitate reply
    replyaddr="\$(cut -d' ' -f1 <<< "\$SSH_CLIENT")"
    # Update known_hosts
    ssh-keyscan -H "\$replyaddr" >> "\$HOME/.ssh/known_hosts"
    # Receive main script
    $(cat)
EOT
}

# q
# Like printf %q but for multiple arguments.
q() {
    local quoted=()
    local arg; for arg in "$@"; do
        quoted+=("$(printf %q "$arg")")
    done
    echo "${quoted[*]}"
}

# ====
# Main
# ====

main() {

    # ---arg parsing---

    if [[ "$1" == -h || "$1" == --help ]]; then usage; exit; fi
    local sshopts=()
    if [[ "$1" == -i ]]; then sshopts+=(-i "$2"); shift 2; fi
    if [[ "$1" == -p ]]; then sshopts+=(-p "$2"); shift 2; fi
    local inbox=/mnt/shared/backups
    if [[ "$1" == -n ]]; then inbox="$2"; shift 2; fi
    # check for relative path
    if [[ "${inbox#/}" == "$inbox" ]]; then
        inbox="$(pwd)/$inbox"
    fi
    # get forwarded arguments and remotes
    local -a forward=()
    local remotelist=/dev/stdin
    local -a remotes=()
    if (( $# )); then
        # set forwarded arguments
        forward=("${@:1:$(($#-1))}")
        # pick where to read remote list from
        remotelist="${@:$#}"
        if [[ "$remotelist" == - ]]; then
            remotelist=/dev/stdin
        fi
    fi
    # if file is readable, read it
    if [[ -r "$remotelist" ]]; then
        local remote; while read remote; do
            remotes+=("$remote")
        done < "$remotelist"
    # otherwise assume it's a single hostname or ip address
    else
        remotes=("$remotelist")
    fi

    # ---real main---

    echo "[checklist.sh] Creating reply key"
    mkreplykey

    # locate and load osxbackup.sh
    local osxbackup;
    if [[ -f "$(dirname "$BASH_SOURCE")/osxbackup.sh" ]]; then
        echo "[checklist.sh] Loading osxbackup.sh"
        osxbackup="$(cat "$(dirname "$BASH_SOURCE")/osxbackup.sh")"
    else
        echo>&2 "[checklist.sh ERROR] no osxbackup.sh"
        exit 1
    fi

    local remote; for remote in "${remotes[@]}"; do
        # convert remote to names (word splitting on purpose)
        local -a names=($(cut -d'|' -f1,2 <<< "$remote"))
        # check if we already have a backup
        echo "[checklist.sh] Searching for existing backup for $remote"
        local any_backup=''
        local name; for name in "${names[@]}"; do
            # skip delimiter
            if [[ "$name" == '|' ]]; then continue; fi
            local backup; for backup in "$inbox/$name-"*; do
                # account for unexpanded wildcard
                if [[ -f "$backup" ]]; then
                    any_backup=:
                    echo "[checklist.sh] Found backup at $backup"
                    break 2 # skip remaining names of same remote
                fi
            done
        done
        # try to make a backup if none
        if [[ ! "$any_backup" ]]; then
            echo "[checklist.sh] No existing backup; trying to connect..."
            for name in "${names[@]}"; do
                # skip delimiter
                if [[ "$name" == '|' ]]; then continue; fi
                echo "[checklist.sh] ... via name $name"
                if ssh-with-reply "${sshopts[@]}" "$name" << EOT
                    echo "[checklist.sh on $name] "`
                        `"Connected; trying to create backup"
                    set -- -C -i\ "\$rundir/replykey"\ `
                            `-o\ StrictHostKeyChecking=no `
                        `$(q "${forward[@]}") `
                        `$USER@\$replyaddr:$inbox`
                            `/$name-\$(date +'%F-%H-%M-%S').gzip
                    $osxbackup
EOT
                then
                    echo "[checklist.sh] OK; "`
                        `"remote session appears to have succeeded; "`
                        `"double-checking to ensure backup has been received"
                    any_backup=''
                    for backup in "$inbox/$name-"*; do
                        # account for unexpanded wildcard
                        if [[ -f "$backup" ]]; then
                            any_backup=:
                            echo "[checklist.sh] Found backup at $backup"
                            break 2 # skip remaining names of same remote
                        fi
                    done
                    if [[ ! "$any_backup" ]]; then
                        echo>&2 "[checklist.sh ERROR] Backup not received"
                    fi
                else
                    echo>&2 "[checklist.sh ERROR] Remote session exited "`
                        `"with nonzero status $?"
                fi
            done
        fi
    done

}

[[ "$CHECKLIST_SH_DEFS_ONLY" ]] || main "$@"
