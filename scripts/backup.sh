#!/bin/bash
# File              : osxbackup.sh
# Date              : 12.02.2022
# Last Modified Date: 16.02.2022
# Last Modified By  : blujai831 <benjamin.i.mccann@gmail.com>

# Objectives
# /Users/$USER/Documents
# /Users/$USER/Desktop
# Zip those files as $USER-Data-Time.gzip
# Make copy of the backup in /Users/Shared
# Upon exit status 0 remove copy in /Users/Shared
# scp the backups to remote server
# check exit status make sure completion of files.



# ===========
# Definitions
# ===========

# usage
# Shows script usage info.
usage() {
cat << EOT
USAGE: $0 [OPTION ...] [PATH ...] DEST
EXAMPLE: $0 -C'-i ~/privkey' ${USER}@${USER}s-other-pc:/Users/$USER
EOT
cat << 'EOT'
By default, archives given PATHs to a gzip, and scp's the archive to DEST,
deleting the archive on success, but leaving it in /Users/Shared on failure.
If no PATHs are given, $HOME/{Documents,Desktop} are assumed.

More generally, archives given PATHs, attempts to process the archive
in some way, and, on failure, processes in it some other way.
The below options can alter the specifics of the behavior.

CAUTION: Note that this script deliberately executes arbitrary shell code
that may be given as optional input. Do not programatically call this script
on arguments passed in by a potentially adversarial end user.

OPTIONS

-a COMMAND
Instead of tar -czf %o %i, use COMMAND for [a]rchival step.
In COMMAND, %i is replaced with the list of PATHs to archive,
and %o is replaced with the BACKUP destination path for the archive.

-A EXTRA_OPTIONS
During [A]rchival step, inject EXTRA_OPTIONS into COMMAND.
If -a is not also given, EXTRA_OPTIONS will be injected
into the default gzip command. EXTRA_OPTIONS will be word-split on eval;
if it contains nested spaces, be mindful of nested quoting.

-b PATH
Instead of /Users/Shared/%u-%d.gzip, use PATH for [b]ackup step.
In PATH, %i is replaced with the PATHs' basenames joined by hyphens ('-'),
%d is replaced with $(date +'%F-%H-%M-%S'),
and %u is replaced with the current username.

-c COMMAND
Instead of scp %i %o, use COMMAND for [c]opying step.
In COMMAND, %i is replaced with the path to the assembled archive,
and %o is replaced with DEST.

-C EXTRA_OPTIONS
During [C]opying step, inject EXTRA_OPTIONS into COMMAND.
If -c is not also given, EXTRA_OPTIONS will be injected
into the default scp command. EXTRA_OPTIONS will be word-split on eval;
if it contains nested spaces, be mindful of nested quoting.

-d COMMAND
Instead of rm -f %i, use COMMAND for [d]eletion step.
In COMMAND, %i is replaced with the original path to the assembled archive,
prior to copying step.

-D EXTRA_OPTIONS
During [D]eletion step, inject EXTRA_OPTIONS into COMMAND.
If -d is not also given, EXTRA_OPTIONS will be injected
into the default rm command. EXTRA_OPTIONS will be word-split on eval;
if it contains nested spaces, be mindful of nested quoting.

-h
Displays this [h]elp message and exits.

-l
Show [l]ist of preexisting backups leftover by prior copy failures.

-k
Skip deletion step; [k]eep local archive backup even if copying step succeeds.

-r
Try to [r]esume; if a backup exists and has not been successfully copied,
copy it instead of creating another. For safety, DEST is required
to be a directory, and this is guaranteed by appending a /; otherwise,
it would be possible for backups to silently overwrite each other
out of order at the destination, and still be removed from the origin
as though copying had succeeded.

-v
Run in [v]erbose mode. Subcommands are echoed.

-v -v
More [v]erbose. Subcommands are echoed, and -v is forwarded to them.
Note that if any custom COMMANDs are given (-acd),
-v -v will only work if those custom COMMANDs support -v.

-W
[W]ipe all preexisting backups and exit.
EOT
}

# init-vars
# Initializes script global variables.
# All of these may be overridden by script arguments (see parse-args).
init-vars() {
    archive_command='tar -czf %o %i'
    backup_path="/Users/Shared/%u-%d.gzip"
    quoted_globbed_backup_path=''
    copy_command='scp %i %o'
    delete_command='rm -f %i'
    action=normal
    verbose=''
    paths_to_archive=("$HOME/Documents" "$HOME/Desktop")
    destination='.'
    old_backups=()
    return 0
}

# inject-options COMMAND OPTIONS_QUOTE
# Puts OPTIONS_QUOTED after the first word of COMMAND.
inject-options() {
    if [[ ! "$1" ]]; then
        # if $1 has been completely disabled,
        # don't accidentally reenable it by trying to add options to it
        :
    elif [[ "${1/ /}" == "$1" ]]; then
        # if $1 is a single word, append
        echo "$1 $2"
    else
        # otherwise replace first whitespace
        echo "${1/ / $2 }"
    fi
}

# parse-args ARGS ...
# Parses command-line arguments.
parse-args() {
    local opt; while getopts 'a:A:b:c:C:d:D:hklrvW' opt; do case "$opt" in
    # -a: set archive_command
    a)  archive_command="$OPTARG" ;;
    # -A: inject options into existing archive_command
    A)  archive_command="$(inject-options "$archive_command" "$OPTARG")" ;;
    # -b: set backup_path
    b)  backup_path="$OPTARG" ;;
    # -c: set copy_command
    c)  copy_command="$OPTARG" ;;
    # -C: inject options into existing copy_command
    C)  copy_command="$(inject-options "$copy_command" "$OPTARG")" ;;
    # -d: set delete_command
    d)  delete_command="$OPTARG" ;;
    # -D: inject options into existing delete_command
    D)  delete_command="$(inject-options "$delete_command" "$OPTARG")" ;;
    # -h: show usage and exit
    h)  action=help ;;
    # -k: skip delete_command and keep backup
    k)  delete_command='notify-about-backup %i' ;;
    # -l: show backup list and exit
    l)  action=list ;;
    # -r: resume if backup exists
    r)  action=resume ;;
    # -v: set verbose
    v)  if [[ "$verbose" ]]; then
            # if already verbose, make all subcommands also verbose
            archive_command="$(inject-options "$archive_command" -v)"
            copy_command="$(inject-options "$copy_command" -v)"
            delete_command="$(inject-options "$delete_command" -v)"
        else
            verbose=:
        fi ;;
    # -W: wipe backups
    W)  action=wipe ;;
    # complain about unrecognized options
    *)  echo>&2 "Unrecognized option. Try $0 -h for help."; exit 1 ;;
    esac; done
    # get PATHs and DEST from rest of args
    shift "$(($OPTIND-1))"
    if (( $# )); then
        if (( $#>1 )); then
            paths_to_archive=()
            while (( $#>1 )); do
                paths_to_archive+=("$1")
            shift; done
        fi
        destination="$1"
        # if -r, enforce directory destination to prevent overwrite madness
        if [[ "$action" == resume ]]; then destination="${destination%/}/"; fi
    fi
}

# quote ARGS ...
# Forms a single string that eval's to the list of strings given.
quote() {
    local tokens_out=()
    local token; for token in "$@"; do
        tokens_out+=("'${token//\'/\'\"\'\"\'}'")
    done
    echo "${tokens_out[*]}"
}

# build-commands
# Replaces % parts of command variables with their proper values.
build-commands() {
    # build backup paths
    local basenames=''
    local path; for path in "${paths_to_archive[@]}"; do
        basenames="${basenames}-"$(basename "$path")""
    done
    backup_path="${backup_path//\%i/${basenames:1}}"
    backup_path="${backup_path//\%u/$USER}"
    # build globbed backup path
    quoted_globbed_backup_path="$(quote "$backup_path")"
    quoted_globbed_backup_path="${quoted_globbed_backup_path//\%d/'*'}"
    # build specific backup path
    backup_path="${backup_path//\%d/$(date +'%F-%H-%M-%S')}"
    # build archive command
    archive_command=`
        `"${archive_command//\%i/$(quote "${paths_to_archive[@]}")}"
    archive_command="${archive_command//\%o/$(quote "$backup_path")}"
    # build copy commands
    copy_command="${copy_command//\%o/$(quote "$destination")}"
    # not building the delete command as there's nothing to do
    # (in copy and delete, we are not replacing %i until we use them,
    # because %i can vary depending on -r / -W)
    return 0
}

# notify-about-backup [PATH]
# Called on error or on -k.
# If not given, PATH defaults to $backup_path.
notify-about-backup() {
    last_arg="${@:$#}"
    if [[ -e "${last_arg:-$backup_path}" ]]; then
        echo "Keeping backup at ${last_arg:-$backup_path}."
    else
        echo "No backup at ${last_arg:-$backup_path} to keep."
    fi
}

# do-eval COMMAND [PATH]
# If verbose, echo COMMAND. Regardless, also eval it.
# If it fails, complain and return nonzero.
# If not given, PATH defaults to $backup_path.
do-eval() {
    if [[ "$verbose" ]]; then
        echo "$1"
    fi
    if eval "$1"; then
        return 0
    else
        status="$?"
        echo>&2 "Error: Command $1 exited with status $status"
        notify-about-backup>&2 "${2:-$backup_path}"
        return "$status"
    fi
}

# do-archive
# Does archive step.
do-archive() {
    do-eval "$archive_command"
}

# do-copy [PATH]
# Does copy step for backup at PATH.
# If not given, PATH defaults to $backup_path.
do-copy() {
    do-eval "${copy_command//\%i/$(quote "${1:-$backup_path}")}" `
        `"${1:-$backup_path}"
}

# do-delete [PATH]
# Does delete step for backup at PATH.
# If not given, PATH defaults to $backup_path.
do-delete() {
    do-eval "${delete_command//\%i/$(quote "${1:-$backup_path}")}" `
        `"${1:-$backup_path}"
}

# find-existing-backups
# Populates old_backups array by eval'ing our quoted glob.
find-existing-backups() {
    eval "old_backups=(${quoted_globbed_backup_path[@]})"
    # check for un-expanded glob
    if (( "${#old_backups[@]}" == 1 )) &&
            [[ ! -f "${old_backups[0]}" ]]; then
        old_backups=()
        return 1
    else
        return 0
    fi
}

# do-selected-action
# Inspect $action and run do-'s accordingly.
do-selected-action() {
    local status=0
    case "$action" in
    # help: display usage and exit
    help)   usage ;;
    # list: show all existing backups
    list)   if find-existing-backups; then
                echo "$(quote "${old_backups[@]}")"
            else
                status=1
            fi ;;
    # resume: skip archiving, copy all existing backups
    resume) if find-existing-backups; then
                local backup; for backup in "${old_backups[@]}"; do
                    do-copy "$backup" && do-delete "$backup"
                    # set status, but do not transition from an error state
                    # back to an OK state
                    local newstatus="$?"
                    if (( "$newstatus" )); then
                        status="$newstatus"
                    fi
                done
            else
                # if no existing backups, fallback to normal
                action=normal
                do-selected-action # recursive call
                status="$?"
            fi ;;
    # wipe: delete all existing backups and exit
    wipe)   if find-existing-backups; then
                local backup; for backup in "${old_backups[@]}"; do
                    do-delete "$backup"
                    # set status, but do not transition from an error state
                    # back to an OK state
                    local newstatus="$?"
                    if (( "$newstatus" )); then
                        status="$newstatus"
                    fi
                done
            else
                status=1
                if [[ "$verbose" ]]; then echo>&2 "Nothing to wipe."; fi
            fi ;;
    # normal: archive-copy-delete, ignore existing backups
    normal) do-archive && do-copy && do-delete
            status="$?" ;;
    # complain if unrecognized
    *)      echo>&2 "script logic error: unrecognized action $action"
            status=1 ;;
    esac
    return "$status"
}



# ===============================
# Effective entry point of script
# ===============================

init-vars
parse-args "$@"
build-commands
do-selected-action
exit "$?"
