#!/bin/bash
# File              : cc-scvc-cb3l.sh
# Date              : 22.03.2022
# Last Modified Date: 18.04.2022
# Last Modified By  : blujai831 <benjamin.i.mccann@gmail.com>

cc-scvc-cb3l-usage() { cat << EOT
Community Connections
Santa Cruz Volunteer Center
Common Bash 3 Library
v0.1.0 r18.04.2022

A common library containing helper functions
for use in Community Connections SCVC OSX bash scripts.

Full library documentation is available in the script text:
    $(basename "${PAGER:-cat}") $(printf '%q' "$0")

Import by sourcing:
    #!/bin/bash
    # [script preamble]
    source "\${CC_SCVC_CB3L:-/usr/local/libexec/$(basename "$0")}"
    # [rest of script]

Install to /usr/local/libexec/$(basename "$0")
by running with --install:
    $(printf '%q' "$0") --install

If an argument is given to --install,
the library is installed to the given directory
instead of to /usr/local/libexec:
    $(printf '%q' "$0") --install /usr/libexec
    # ^ Would install to /usr/libexec/cc-scvc-cb3l.sh instead.
Just remember to set CC_SCVC_CB3L in an appropriate place,
e.g. your profile, if you choose to install in this way.
EOT
}

shopt -s extglob

# =====================
# Reliable finalization
# =====================

# ${AT_EXIT[@]}
# Global array variable containing a list of functions to call on exit.
# Function at-exit initializes the exit trap that calls these functions;
# they will not be called unless at-exit has been called at least once,
# so, when using this library, it is recommended to add new exit traps
# only via at-exit.
AT_EXIT=()

# ${AT_EXIT_DO_LAST[@]}
# Like AT_EXIT, but actions here will always succeed all actions in AT_EXIT,
# and the initializing function is at-exit-do-last instead of at-exit.
# Functions added here should not rely on the existence of $RUNDIR,
# as its deletion step is added via at-exit-do-last.
AT_EXIT_DO_LAST=()

# do-each FUNC ...
# Calls each FUNC, in sequence, each with no arguments.
do-each() {
    local func; for func in "$@"; do "$func"; done
}

# at-exit FUNC ...
# Prepends the given list of FUNCs to AT_EXIT.
# Also sets the exit trap to do-each "${AT_EXIT[@]}" "${AT_EXIT_DO_LAST[@]}".
at-exit() {
    trap 'do-each "${AT_EXIT[@]}" "${AT_EXIT_DO_LAST[@]}"' EXIT
    AT_EXIT=("$@" "${AT_EXIT[@]}")
}

# at-exit-do-last FUN ...
# Appends the given list of FUNCs to AT_EXIT_DO_LAST.
# Also sets the exit trap to do-each "${AT_EXIT[@]}" "${AT_EXIT_DO_LAST[@]}".
at-exit-do-last() {
    trap 'do-each "${AT_EXIT[@]}" "${AT_EXIT_DO_LAST[@]}"' EXIT
    AT_EXIT_DO_LAST+=("$@")
}

# ================================
# Debugging, logging, unit-testing
# ================================

# cc-scvc-cb3l-path
# Echoes the path to this library, or the path to the copy in the rundir
# if there is such a copy. (The copy's contents are not checked,
# only its filename.)
cc-scvc-cb3l-path() {
    if [[ "$RUNDIR" &&
            -d "$RUNDIR" &&
            -f "$RUNDIR/cc-scvc-cb3l.sh" ]]
    then
        echo "$RUNDIR/cc-scvc-cb3l.sh"
    else
        echo "$BASH_SOURCE"
    fi
}

# calling-context [DEPTH]
# Outputs a verbose description of where the caller was called:
# the name of the caller's caller,
# the line number where the caller's caller calls the caller,
# and the basename of the file where the caller's caller is defined,
# in that order, separated with @ and :, in that order:
#   FUNC@LINE:FILE
#
# If DEPTH is given, outputs a verbose description
# of where the caller's $DEPTH'th ancestor in the call stack was called,
# instead of where the caller was called.
#
# If environment variable CALLING_CONTEXT_SHELL_NAME exists,
# prepends it with a vertical bar:
#   $CALLING_CONTEXT_SHELL_NAME|FUNC@LINE:FILE
#
# Known issue: Line number will probably be relative
# to either the beginning of the file or the beginning of the function.
# Which one appears to be unpredictable,
# and I don't know how to solve that problem.
calling-context() {
    if [[ "$CALLING_CONTEXT_SHELL_NAME" ]]; then
        echo -n "$CALLING_CONTEXT_SHELL_NAME|"
    fi
    local depth=0
    if (( $# )); then depth=$1; fi
    echo "${FUNCNAME[$((depth+2))]}"`
        `"@${BASH_LINENO[$((depth+1))]}"`
        `":$(basename "${BASH_SOURCE[$((depth+2))]}")"
}

# $LOG_LEVEL
# Informs behavior of log. Can also be set with log.
# Valid values are integers upward from 0 inclusive. Default is 3.
# LEVEL_OPTIONs are mapped to values as follows:
#   -1  setting:    -a
#                   --all
#       logging:    [none; do not use this level for logging]
#   0   setting:    -s
#                   -qqq
#                   --silent
#       logging:    [none; do not use this level for logging]
#   1   setting:    -qq
#                   --quieter
#                   --no-warnings
#                   --only-errors
#       logging:    --error
#       either:     -e
#   2   setting:    -q
#                   --quiet
#       logging:    --warn
#                   --warning
#       either:     -w
#   3   setting:    --notices
#                   -r
#                   --reset
#       logging:    [none; simply omit the LEVEL_OPTION to use this level]
#       either:     -n
#                   --normal
#                   --notice
#                   -i
#                   --info
#   4   setting:    --successes
#       either:     -o
#                   --ok
#                   --success
#   5   either:     -v
#                   --verbose
#   6   either:     -vv
#                   --more-verbose
#                   -d
#                   --debug
#   7   either:     -vvv
#   8   either:     -vvvv
#   ...
# "Setting" and "logging" indicate whether the option is approriate
# for setting the log level to the applicable number
# or for logging a message at that log level, respectively.
# Each nonnegative log level includes itself and all lesser log levels
# but excludes all greater log levels.
# Log level -1 includes all log levels.
# Only messages included under $LOG_LEVEL by this logic
# are actually logged when sent to log.
LOG_LEVEL="${LOG_LEVEL:-3}"

# $LOG_FILE
# If this is nonempty, messages from log are copied here.
LOG_FILE="${LOG_FILE:-}"

# log [--force-color] [--context DEPTH] [LEVEL_OPTION] [MESSAGE ...]
# Logs a message or sets $LOG_LEVEL. Copies to $LOG_FILE if variable exists.
#
# If --force-color is given, it must be given first.
#
# If --context is given, it must be given first
# (but after --force-color if --force-color is given),
# and DEPTH is passed to calling-context.
# LEVEL_OPTIONs, if given, must be as defined under $LOG_LEVEL.
# MESSAGE is logically considered one message but may be multiple shell words.
#
# If both a LEVEL_OPTION and a MESSAGE are given,
# logs the MESSAGE at the log level given by the LEVEL_OPTION.
# If only a MESSAGE is given and no LEVEL_OPTION,
# logs the MESSAGE at log level 3.
# Regardless, logs to stderr, prepends info gathered from calling-context,
# and, if stderr is a tty, may color-code the message by log level.
# (Of course, if the message's log level is not included under $LOG_LEVEL,
# all of this output is suppressed.)
#
# If only a LEVEL_OPTION is given and no MESSAGE, sets LOG_LEVEL.
# If neither is given, reports the current LOG_LEVEL to stdout,
# represented as one of its mapped LEVEL_OPTIONs
# rather than in its pure integer form.
# The reported LEVEL_OPTION will be appropriate for all functions
# which the corresponding LOG_LEVEL allows, whether that be both or only one.
log() {
    local depth=0 level=3 message=() force_color=''
    # detect --force-color
    if [[ "$1" == --force-color ]]; then
        shift
        force_color=:
    fi
    # detect --context
    if [[ "$1" == --context ]]; then
        shift
        depth="$1"
        shift
    fi
    # choose what to do
    case $# in
    # no args: print current log level and return
    0)  case "$LOG_LEVEL" in
        -1) printf "%s\n" -a ;;
        0)  printf "%s\n" -s ;;
        1)  printf "%s\n" -e ;;
        2)  printf "%s\n" -w ;;
        3)  printf "%s\n" -n ;;
        4)  printf "%s\n" -o ;;
        *)  if (( LOG_LEVEL >= 5 )); then
                printf "%s" -
                for (( level=5; level <= LOG_LEVEL; level++ )); do
                    printf "%s" v
                done
                printf "\n"
            else
                return 1
            fi ;;
        esac
        return 0 ;;
    # 1 arg: assess whether arg is a setting LOG_OPTION;
    # if it is, set and return
    1)  case "$1" in
        -a|--all)
            LOG_LEVEL=-1
            return 0 ;;
        -s|-qqq|--silent)
            LOG_LEVEL=0
            return 0 ;;
        -e|-qq|--quieter|--no-warnings|--only-errors)
            LOG_LEVEL=1
            return 0 ;;
        -w|-q|--quiet)
            LOG_LEVEL=2
            return 0 ;;
        -n|--normal|--notice|--notices|-r|--reset|-i|--info)
            LOG_LEVEL=3
            return 0 ;;
        -o|--ok|--success|--successes)
            LOG_LEVEL=4
            return 0 ;;
        -v|--verbose)
            LOG_LEVEL=5
            return 0 ;;
        -vv|--more-verbose|-d|--debug)
            LOG_LEVEL=6
            return 0 ;;
        -+(v))
            LOG_LEVEL=$((${#1}+3))
            return 0 ;;
        # if arg isn't a setting LOG_OPTION, use it as a message
        *)  message=("$1") ;;
        esac ;;
    # >=2: assess whether first arg is a logging LOG_OPTION;
    # if it is, use it
    *)  message=("${@:2}")
        case "$1" in
        -e|--error)
            level=1 ;;
        -w|--warn|--warning)
            level=2 ;;
        -n|--normal|--notice|-i|--info)
            level=3 ;;
        -o|--ok|--success)
            level=4 ;;
        -v|--verbose)
            level=5 ;;
        -vv|--more-verbose|-d|--debug)
            level=6 ;;
        -+(v))
            level=$((${#1}+3)) ;;
        # if first arg isn't a logging LOG_OPTION,
        # include it in the message, and use log level 3
        *)  level=3
            message=("$@") ;;
        esac ;;
    esac
    # if we got here, the action we're taking
    # is guaranteed to be logging a message
    # (because all other actions return when they finish)
    # so check if we can log at the requested level
    if (( level <= LOG_LEVEL || LOG_LEVEL < 0 )); then
        # apply heading
        # error, warn, ok, debug: context + log level name
        # plain notice: message is completely undecorated
        # verbose but *not* debug: context but no log level name
        case "$level" in
        1)  message=("[$(calling-context $depth)] ERROR:" "${message[@]}") ;;
        2)  message=("[$(calling-context $depth)] WARN:" "${message[@]}") ;;
        3)  : ;;
        4)  message=("[$(calling-context $depth)] OK:" "${message[@]}") ;;
        5)  message=("[$(calling-context $depth)]" "${message[@]}") ;;
        *)  message=("[$(calling-context $depth)] DEBUG:" "${message[@]}") ;;
        esac
        # check if stderr is a tty, and set formatting if so
        if [[ "$force_color" || -t 2 ]]; then
            case "$level" in
            1)  echo>&2 -en "\x1b[31m" ;;   # -e: red
            2)  echo>&2 -en "\x1b[33m" ;;   # -w: yellow
            3)  : ;;                        # -n: no color
            4)  echo>&2 -en "\x1b[32m" ;;   # -o: green
            5)  : ;;                        # -v: no color
            *)  if (( level >= 6 )); then
                    echo>&2 -en "\x1b[36m"  # -d / -vv+: cyan
                fi ;;
            esac
        fi
        # print message, copy to $LOG_FILE if exists
        echo>&2 -n "${message[*]}"
        if [[ "$LOG_FILE" && -d "$(dirname "$LOG_FILE")" ]]; then
            if [[ ! -f "$LOG_FILE" ]]; then
                touch "$LOG_FILE"
            fi
            echo "${message[*]}" >> "$LOG_FILE"
        fi
        # if stderr is a tty, we may have set formatting, so unset it
        if [[ "$force_color" || -t 2 ]]; then
            echo>&2 -e "\x1b[0m"
        else
            # otherwise, we still have a line going, so end the line
            echo>&2
        fi
    fi
}

# log-pregen ARG ...
# Forwards ARGs to log. Redirects log's stderr to stdout for capturing.
# However, the tty check for formatting is still based on log-pregen's stderr.
# (It is assumed the log message will later be sent to the same stderr
# which was given to log-pregen.)
log-pregen() {
    ( # <-- subshell because we unset LOG_FILE
        LOG_FILE=''
        if [[ "$1" == --force-color ]]; then
            shift
            log "$@" 2>&1
        elif [[ -t 2 ]]; then
            log --force-color "$@" 2>&1
        else
            log "$@" 2>&1
        fi
    )
}

# assert [--context DEPTH] [--eval] COMMAND ARG ... [--or-else MESSAGE ...]
# Runs COMMAND ARG ... . If it fails, produces an informative error message,
# overridden by --or-else MESSAGE if given. Logs an executed assertion
# in any case, and a passed assertion on success,
# if we are in a unit test process (PROCESS_IS_UNIT_TEST); otherwise,
# exits on failure. Options --context and --eval, if both present,
# must be given in that order, and option --or-else terminates ARGs
# (meaning, unfortunately, it is not possible to pass literal --or-else
# to COMMAND without eval). --context changes DEPTH to use
# for calling-context in reporting failures; --eval causes the command given
# to be run with eval instead of as an array.
assert() {
    local exit_status=0
    # determine calling context to use in reporting
    local depth=1
    if [[ "$1" == --context ]]; then
        shift
        depth=$(($1 + 1))
        shift
    fi
    # determine whether to use eval
    local use_eval
    if [[ "$1" == --eval ]]; then
        use_eval=:
        shift
    fi
    # collect command and determine if we have an or_else
    local command=() or_else=()
    while (( $# )); do
        if [[ "$1" == --or-else ]]; then
            shift
            or_else=("$@")
            break
        else
            command+=("$1")
            shift
        fi
    done
    # run command and check its exit status
    if [[ "$use_eval" ]]; then
        eval "${command[*]}"
        exit_status=$?
    else
        "${command[@]}"
        exit_status=$?
    fi
    # report result
    if (( $exit_status != 0 )); then
        if (( ${#or_else[@]} )) && ! [[ "$PROCESS_IS_UNIT_TEST" ]]; then
            log --context $depth -e "${or_else[*]}"
        else
            log --context $depth -e `
                `"Assertion '${command[*]}' failed "`
                `"with exit status $exit_status"
        fi
    fi
    # decide how to proceed
    # if PROCESS_IS_UNIT_TEST: tally assertions
    if [[ "$PROCESS_IS_UNIT_TEST" ]]; then
        if ! [[ "$ASSERTIONS_MADE" && "$ASSERTIONS_PASSED" ]]; then
            ASSERTIONS_MADE=0
            ASSERTIONS_PASSED=0
            at-exit-do-last show-assert-tallies-and-exit
        fi
        ((ASSERTIONS_MADE++))
        if (( exit_status == 0 )); then
            ((ASSERTIONS_PASSED++))
        fi
    # otherwise: do not tolerate failure
    elif (( exit_status == 0 )); then
        return 0
    else
        if ! (( ${#or_else[@]} )); then
            log --context $depth -e `
                `"An assertion failed outside unit testing; exiting"
        fi
        exit $exit_status
    fi
}

# show-assert-tallies-and-exit [INITIAL_EXIT_CODE]
# Compares $ASSERTIONS_PASSED to $ASSERTIONS_MADE,
# prints diagnostic info about the comparison and INITIAL_EXIT_CODE to stderr,
# and then decides on a final exit code and exits.
# If $INITIAL_EXIT_CODE != 0, final exit code is $INITIAL_EXIT_CODE;
# else, if $ASSERTIONS_PASSED >= $ASSERTIONS_MADE, final exit code is 0;
# else, final exit code is 1. If not given,
# INITIAL_EXIT_CODE is assumed to be $?.
show-assert-tallies-and-exit() {
    local initial_exit_code=${1:$?}
    # initialize local vars for shorthand
    local made=${ASSERTIONS_MADE:-0}
    local passed=${ASSERTIONS_PASSED:-0}
    local failed=$((made-passed))
    local message
    # determine how to represent number of assertions made
    # (if $initial_exit_code is nonzero, then,
    # instead of an authoritative total number of assertions intended,
    # $made represents a lower limit on the unknowable number of assertions
    # that might have been intended)
    local intended
    if (( initial_exit_code == 0 )); then
        intended="$made"
    else
        intended="at least $made"
    fi
    # compose report
    if (( made > 0 )); then
        if (( passed > 0 )); then
            message="$passed/$intended assertions passed."
            if (( passed >= made )) &&
                (( initial_exit_code == 0 ))
            then
                log -o "$message"
            else
                log -w "$message"
            fi
        fi
        if (( failed > 0 )); then
            log -e "$failed of $intended assertions failed."
        fi
    elif (( initial_exit_code == 0 )); then
        log -w "No assertions made."
    else
        log -w "No assertions reached."
    fi
    if (( initial_exit_code == 0 )); then
        exit $(( passed < made ))
    else
        log -e "Exited with nonzero exit code $initial_exit_code."
        exit $initial_exit_code
    fi
}

# $PROCESS_IS_UNIT_TEST
# Set by subshells started by unit-test. If this variable is nonempty,
# it is meant to indicate that the current bash process is a unit test.
# This changes the behavior of assertions.
PROCESS_IS_UNIT_TEST=''

# unit-test FUNC ...
# Calls unit-test:$FUNC for each FUNC, announcing to stderr each such call.
# If no arguments, calls every function that begins with unit-test:.
# Runs each unit test in a subshell so that the test may fail in any way
# without bringing the test framework down with it.
# Returns 0 iff all unit tests pass (even vacuously).
unit-test() ( # <-- subshell function
    log --all
    local funcs=() message
    # try to get unit tests from args
    if (( $# )); then
        for func in "$@"; do funcs+=("unit-test:$func"); done
    # if no args, run all unit tests
    else
        funcs=($(compgen -A function unit-test:))
    fi
    # run and tally each unit test
    local func passed=0 total=${#funcs[@]} i=0 name
    for func in "${funcs[@]}"; do
        ((i++))
        name="${func#unit-test:}"
        log -v "===Running unit test: $i/$total for $name==="
        if (
            RUNDIR='' # <-- Prevent unit tests from deleting caller's rundir
            PROCESS_IS_UNIT_TEST=:
            "$func"
        ); then
            log -o "Unit test passed: $i/$total for $name."
            ((passed++))
        else
            log -e "Unit test failed: $i/$total for $name."
        fi
    done
    local failed=$((total-passed))
    # compose report
    log -v "===Final results of unit testing==="
    if (( total > 0 )); then
        if (( passed > 0 )); then
            message="$passed/$total unit tests passed."
            if (( passed >= total )); then
                log -o "$message"
            else
                log -w "$message"
            fi
        fi
        if (( failed > 0 )); then
            log -e "$failed/$total unit tests failed."
        fi
    else
        log -w "There were no unit tests to run."
    fi
    return $(( passed < total ))
)

# test-shell [FILE]
# Interactive unit test.
test-shell() {
    if (( $# )) ; then
        bash "${@:1:$(($#-1))}" --init-file <(cat << EOT
            if [[ -f $(printf '%q' "$HOME/.bashrc") ]]; then
                source $(printf '%q' "$HOME/.bashrc")
            fi
            source $(printf '%q' "$1")
            log -a
            CALLING_CONTEXT_SHELL_NAME=test-shell
            ensure-rundir
            LOG_FILE="\$RUNDIR/test-log"
            unit-test
            assert cp "$(cc-scvc-cb3l-path)" "\$RUNDIR" `
                `--or-else "Could not copy library into rundir."
            cd "\$RUNDIR"
            export PS1="[TEST SHELL] \$PS1"
            PROCESS_IS_UNIT_TEST=:
            log "Begin interactive test shell."
EOT
        )
    else
        test-shell "$(cc-scvc-cb3l-path)"
    fi
}

# =======================================
# Parsing and string / array manipulation
# =======================================

# check-arity ARITY ARG ... NEXT_ARG
# Helper function for parse-opts.
# Determines the effect of processing NEXT_ARG
# when a current option with ARITY has already consumed ARGs.
#
# ARITY marks the number of arguments some unstated current option accepts,
# as distinct from, but nested within, the total number of arguments
# the also-unstated function for which parsing is being performed accepts.
# So, for instance, if command COMMAND accepts option --OPTION,
# which has arity ARITY, and an invocation of COMMAND appears as follows:
#   COMMAND --OPTION ARG ... --OTHER_OPTION OTHER_ARG ... --ETC ...
# ... then ARITY applies only to ARG ..., as in --OPTION ARG ...;
# it is irrelevant to the following options, namely OTHER_OPTION and ETC ...,
# which may have their own distinct arities.
#
# A valid text value of ARITY must match any PATTERN in the below table.
#
#   PATTERN             MATCH IF                ALLOW SUB-OPTIONS
#   (empty / omitted)   # = 0                   no
#   :                   # = 1                   no
#   ::                  # <= 1                  no
#   :- or :+            # >= 1                  no
#   ::- or ::+          always                  no
#   :N                  # = N                   no
#   ::N                 # = 0 or # = N          no
#   :N- or :N+          # >= N                  no
#   ::N- or ::N+        # = 0 or # >= N         no
#   :-M                 0 < # <= M              no
#   ::-M                # <= M                  no
#   :N-M                N <= # <= M             no
#   ::N-M               # = 0 or N <= # <= M    no
#   :o                  # = 1                   yes
#   ::o                 # <= 1                  yes
#   :-o or :+o          # >= 1                  yes
#   ::-o or ::+o        always                  yes
#   :No                 # = N                   yes
#   ::No                # = 0 or # = N          yes
#   :N-o or :N+o        # >= N                  yes
#   ::N-o or ::N+o      # = 0 or # >= N         yes
#   :-Mo                0 < # <= M              yes
#   ::-Mo               # <= M                  yes
#   :N-Mo               N <= # <= M             yes
#   ::N-Mo              # = 0 or N <= # <= M    yes
#   :O                  # = 1                   exclusively
#   ::O                 # <= 1                  exclusively
#   :-O or :+O          # >= 1                  exclusively
#   ::-O or ::+O        always                  exclusively
#   :NO                 # = N                   exclusively
#   ::NO                # = 0 or # = N          exclusively
#   :N-O or :N+O        # >= N                  exclusively
#   ::N-O or ::N+O      # = 0 or # >= N         exclusively
#   :-MO                0 < # <= M              exclusively
#   ::-MO               # <= M                  exclusively
#   :N-MO               N <= # <= M             exclusively
#   ::N-MO              # = 0 or N <= # <= M    exclusively
#
# The meaning of the ARITY is then assigned according to the other columns
# in that row of the table, where # is the number of ARGs
# that actually appear in the command invocation,
# and to which ARITY must match for a successful parse,
# and a "sub-option" is an option treated as an ARG
# to the unstated current option, instead of as another top-level option
# to the also-unstated larger function for which parsing is being performed.
#
# Also, in the above PATTERNs, the capital letters N and M are stand-ins
# for nonnegative integers, but lowercase and capital O's
# are to be taken literally, except when clearly as part of an English word
# informally elaborating on the pattern ("omitted", "or").
#
# To restate the rules in the above table in a broad but informal manner,
# an empty or missing arity indicates no arguments are allowed to the option;
# a prefix of one colon indicates mandatory arguments to the option;
# a prefix of two colons indicates optional arguments to the option;
# a hyphen reads as "through," and, wherever the upper bound is omitted,
# the hyphen may optionally be replaced with a plus, to read as "or more;"
# the number of arguments to the option, if not given
# after the prefix of colons at all, is assumed to be 1;
# a suffix of literal lowercase o indicates arguments *may* be sub-options;
# and a suffix of literal capital O indicates arguments *must* be sub-options.
# Note that "empty or missing" means "empty" for the purposes of check-arity;
# the arity may be missing from parse-opts, but even if it is,
# check-arity requires it as an empty string.
#
# The output of check-arity is one of the following strings,
# and indicates what meaning parse-opts should assign to NEXT_ARG:
#   separator               Terminates arguments to option. Applies only to --
#   argument                Additional argument to option.
#   option                  Additional top-level option.
#   positional              Terminates top-level options as first positional.
#   error-insufficient      Would terminate arguments to option but can't yet.
#   error-excessive         Already too many arguments to option.
#
# Returns 0 in exactly all cases in which output does not begin with "error."
#
# Known limitation: There is no feasible way for check-arity
# to correctly identify the number of sub-options packed together
# in a short option group received as an argument
# under an arity that permits sub-options. To do this,
# check-arity would have to know how user-defined processing
# for the option currently in effect ultimately plans to parse
# that option's own arguments, particularly which
# of the option's short sub-options are non-nullary.
# Because this is not feasible, check-arity always identifies
# short option groups in sub-option contexts as single sub-options.
# Current suggested workaround: avoid relying on arities
# that accept sub-options and also impose upper or lower numeric limits.
# Arities that accept sub-options, but do *not* impose
# upper or lower numeric limits, should still work fine.
check-arity() {
    assert --eval "(( $# >= 2 ))"
    local arity="$1" args=("${@:2:$(($#-2))}") next_arg="${@:$#}"
    local required lower_limit upper_limit opts_ok
    # check if args required
    case "$arity" in
    '') required=forbidden ;;
    ::*) arity="${arity#::}" ;;
    :*) required=:; arity="${arity#:}" ;;
    *)  assert false --or-else "Bad arity: '$arity'." ;;
    esac
    # special-case processing for empty arity
    if [[ "$required" == forbidden ]]; then
        if (( ${#args[@]} > 0 )); then
            echo error-excessive
            return 1
        else
            case "$next_arg" in
            -)  echo positional ;;
            --) echo separator ;;
            -*) echo option ;;
            *)  echo positional ;;
            esac
            return 0
        fi
    fi
    # check if opts ok
    case "$arity" in
    *o) opts_ok=::; arity="${arity%o}" ;;
    *O) opts_ok=:; arity="${arity%O}" ;;
    *)  : ;;
    esac
    # extract lower and upper limits
    case "$arity" in
    '') upper_limit=1 ;;
    -|+) : ;;
    +([[:digit:]]))
        lower_limit=$arity
        upper_limit=$arity ;;
    +([[:digit:]])[-+])
        lower_limit=${arity%[-+]} ;;
    -+([[:digit:]]))
        upper_limit=${arity#-} ;;
    +([[:digit:]])-+([[:digit:]]))
        lower_limit=${arity%-+([[:digit:]])}
        upper_limit=${arity#+([[:digit:]])-} ;;
    *)  assert false --or-else `
            `"Internal cc-scvc-cb3l library error while parsing arity." ;;
    esac
    # determine lower limit if missing
    if [[ ! "$lower_limit" ]]; then
        if [[ "$required" ]]; then
            lower_limit=1
        else
            lower_limit=0
        fi
    fi
    # check for error-excessive
    if [[ "$upper_limit" ]] && (( ${#args[@]} > upper_limit )); then
        echo error-excessive
        return 1
    else
        # stage-1 determination will be used to inform final decision;
        # it is "what would the answer be if there were no numeric limits";
        # stage1_fail is what answer to give if numeric limits forbid
        # giving the answer stored in stage1
        local stage1 stage1_fail
        case "$opts_ok" in
        '') case "$next_arg" in
            -)  stage1=argumentl stage1_fail=positional ;;
            --) stage1=separator ;;
            -*) stage1=option ;;
            *)  stage1=argument; stage1_fail=positional ;;
            esac ;;
        :)  case "$next_arg" in
            -)  stage1=positional ;;
            --) stage1=separator ;;
            -*) stage1=argument; stage1_fail=option ;;
            *)  stage1=positional ;;
            esac ;;
        ::) case "$next_arg" in
            -)  stage1=argument; stage1_fail=positional ;;
            --) stage1=separator ;;
            -*) stage1=argument; stage1_fail=option ;;
            *)  stage1=argument; stage1_fail=positional ;;
            esac ;;
        *)  assert false --or-else `
                `"Internal cc-scvc-cb3l library error: "`
                `"bad opts_ok: '$opts_ok'." ;;
        esac
        # stage-2 of sorts
        if [[ "$stage1" == argument ]]; then
            # if stage1=argument and it would put us over the limit,
            # use stage1_fail
            if [[ "$upper_limit" ]] && (( ${#args[@]} >= upper_limit )); then
                echo "$stage1_fail"
                return 0
            # if it wouldn't put us over the limit, use stage1
            else
                echo "$stage1"
                return 0
            fi
        # check for omission of optional argument list
        elif [[ ! "$required" ]] && (( ${#args[@]} == 0 )); then
            echo "$stage1"
            return 0
        # check for error-insufficient
        elif (( ${#args[@]} < lower_limit )); then
            echo error-insufficient
            return 1
        # finally, if all prior checks have failed,
        # the only explanation is that we're ending off,
        # but within the allowed limits
        else
            echo "$stage1"
            return 0
        fi
    fi
}
unit-test:check-arity() {
    # autca stands for "assertion in unit-test:check-arity"
    autca() {
        assert --eval "(( $# >= 3 ))"
        local ca_args=("${@:1:$(($#-1))}") expected="${@:$#}"
        assert --context 1 test `
            `"$(check-arity "${ca_args[@]}")" = "$expected"
    }
    autca '' -- separator
    autca '' -a option
    autca '' a positional
    autca '' a -- error-excessive
    autca : -- error-insufficient
    autca : -a error-insufficient
    autca : a argument
    autca : a -- separator
    autca : a -b option
    autca : a b positional
    autca : a b -- error-excessive
    autca :: -- separator
    autca :: -a option
    autca :: a argument
    autca :: a -- separator
    autca :: a -b option
    autca :: a b positional
    autca :: a b -- error-excessive
    autca :+ -- error-insufficient
    autca :+ -a error-insufficient
    autca :+ a argument
    autca :+ a -- separator
    autca :+ a -b option
    autca :+ a b argument
    autca ::+ -- separator
    autca ::+ -a option
    autca ::+ a argument
    autca ::+ a -- separator
    autca ::+ a -b option
    autca ::+ a b argument
    autca :2 -- error-insufficient
    autca :2 -a error-insufficient
    autca :2 a argument
    autca :2 a -- error-insufficient
    autca :2 a -b error-insufficient
    autca :2 a b argument
    autca :2 a b -- separator
    autca :2 a b -c option
    autca :2 a b c positional
    autca :2 a b c -- error-excessive
    autca ::2 -- separator
    autca ::2 -a option
    autca ::2 a argument
    autca ::2 a -- error-insufficient
    autca ::2 a -b error-insufficient
    autca ::2 a b argument
    autca ::2 a b -- separator
    autca ::2 a b -c option
    autca ::2 a b c positional
    autca ::2 a b c -- error-excessive
    autca :2+ -- error-insufficient
    autca :2+ -a error-insufficient
    autca :2+ a argument
    autca :2+ a -- error-insufficient
    autca :2+ a -b error-insufficient
    autca :2+ a b argument
    autca :2+ a b -- separator
    autca :2+ a b -c option
    autca :2+ a b c argument
    autca ::2+ -- separator
    autca ::2+ -a option
    autca ::2+ a argument
    autca ::2+ a -- error-insufficient
    autca ::2+ a -b error-insufficient
    autca ::2+ a b argument
    autca ::2+ a b -- separator
    autca ::2+ a b -c option
    autca ::2+ a b c argument
    autca :2-3 -- error-insufficient
    autca :2-3 -a error-insufficient
    autca :2-3 a argument
    autca :2-3 a -- error-insufficient
    autca :2-3 a -b error-insufficient
    autca :2-3 a b argument
    autca :2-3 a b -- separator
    autca :2-3 a b -c option
    autca :2-3 a b c argument
    autca :2-3 a b c -- separator
    autca :2-3 a b c -d option
    autca :2-3 a b c d positional
    autca :2-3 a b c d -- error-excessive
    autca ::2-3 -- separator
    autca ::2-3 -a option
    autca ::2-3 a argument
    autca ::2-3 a -- error-insufficient
    autca ::2-3 a -b error-insufficient
    autca ::2-3 a b argument
    autca ::2-3 a b -- separator
    autca ::2-3 a b -c option
    autca ::2-3 a b c argument
    autca ::2-3 a b c -- separator
    autca ::2-3 a b c -d option
    autca ::2-3 a b c d positional
    autca ::2-3 a b c d -- error-excessive
}

# pack-words ARG ...
# Reversibly packs shell words together.
# They can be unpacked with unpack-words.
pack-words() {
    local out=() arg
    for arg in "$@"; do
        out+=("$(printf %q "$arg")")
    done
    echo "${out[*]}"
}

# unpack-words [+] VAR PACKED ...
# Takes shell words packed together in PACKED
# and unpacks them to an array in VAR.
# PACKED should be passed as word-split (not quoted).
# If + is given, appends instead of setting.
unpack-words() {
    if [[ "$1" == '+' ]]; then
        eval "$2+=(${@:3})"
    else
        eval "$1=(${@:2})"
    fi
}
unit-test:pack-unpack-words() {
    unpack-words words $(pack-words a '"' b '"' c "'" "d e" "'" '\ \ f')
    assert test "${words[*]}" = 'a " b " c '"' d e '"' \ \ f'
    assert --eval "(( ${#words[@]} == 9 ))"
}

# shift-var VAR [N]
# Like shift, but for arrays other than the current positional arguments.
shift-var() {
    case $# in
    1)  eval "$1"'=("${'"$1"'[@]:1}")' ;;
    2)  eval "$1"'=("${'"$1"'[@]:'"$2"'}")' ;;
    *)  assert false --or-else "Too few arguments to shift-var." ;;
    esac
}

# extract-optargs VAR_OUT VAR_IN
# Caller-side helper for parse-pots. Sets VAR_OUT to an empty array. Next,
# repeatedly removes the first element from VAR_IN and appends it to VAR_OUT,
# until -- is encountered or VAR_IN is empty. If -- is encountered,
# also removes --, but does not append it to VAR_OUT.
# The end result is this: assuming VAR_IN contains multiple sublists
# separated by --, removes the first sublist and assigns it to VAR_OUT.
extract-optargs() {
    assert --eval "(( $# == 2 ))" `
        `--or-else "Wrong number of arguments to extract-optargs."
    eval "$1=()"
    while eval '(( ${#'"$2"'[@]} > 0 ))'; do
        if [[ "${!2}" == -- ]]; then
            shift-var "$2"
            break
        else
            unpack-words + "$1" $(pack-words "${!2}")
            shift-var "$2"
        fi
    done
}

# parse-opts ORDER_VAR PATTERN ... POSN_VAR -- ARG ...
#   PATTERN: [-SHORT | --LONG] OPT_VAR [ARITY]
# Parses ARGs according to PATTERNs and stores matches to *_VARs.
# See check-arity for meaning of ARITY.
#
# This function is provided because OSX does not have GNU getopt preinstalled
# and provides no means of parsing long options by default.
#
# Example:
#   parse-opts a -1 b -2 c : --opt3 d :: e -- -12f -2g --opt3 h i j k
#   =>  a=(b c c d)
#       b=(--)
#       c=(f -- g --)
#       d=(h --)
#       e=(i j k)
#
# Note that short option groups (e.g. -ijk as synonymous
# for either -i jk, -i -j k, or -i -j -k) are allowed in ARGs
# (if sanctioned in corresponding PATTERNs for each grouped option),
# but not allowed in PATTERNs.
#
# Each OPT_VAR created by parse-opts (but not the POSN_VAR)
# may contain multiple argument sub-arrays separated by --.
# Regardless, each sub-array, even if there is only one,
# will be terminated by --.
#
# The order in which OPT_VARs were assigned is written to ORDER_VAR.
# This is also the order in which options were encountered.
# In the example above, a=(b c c d) tells us options occurred
# in the following order:
#   -1, writing to b;
#   -2, writing to c;
#   -2 again, writing to c again;
#   --opt3, writing to d.
#
# Therefore, it is possible for the caller to iterate the parse
# in correct order by iterating over ORDER_VAR and using extract-optargs.
#
# Example:
#   if parse-opts `
#       `a -1 b -2 c : --opt3 d :: e -- `
#       `-12f -2g --opt3 h i j k
#   then
#       for var in "${a[@]}"; do
#           extract-optargs optargs "$var"
#           case "$var" in
#           b)  ... ;; # processing for -1
#           c)  ... ;; # processing for -2
#           d)  ... ;; # processing for --opt3
#           *)  assert false ;;
#           esac
#       done
#   else
#       ... # processing for parse error
#   fi
parse-opts() {
    # separate criteria from args
    local criteria=()
    while (( $# )) && [[ "$1" != -- ]]; do
        criteria+=("$1")
        shift
    done
    shift
    # separate criteria out into specifics
    assert --eval "(( ${#criteria[@]} >= 2 ))" `
        `--or-else "Too few arguments to parse-opts."
    local order_var="${criteria[0]}"
    local patterns=("${criteria[@]:1:$((${#criteria[@]}-2))}")
    local posn_var="${criteria[$((${#criteria[@]}-1))]}"
    # init other parse variables
    local opt opt_group opt_var opt_arity opt_args=() arg
    unpack-words "$order_var"
    unpack-words "$posn_var"
    # begin parse
    while (( $# )); do
        opt=''
        opt_group=''
        opt_var=''
        opt_arity=''
        opt_args=()
        arg=''
        # if we are at top-
        # check form of first argument; we are at top-level
        # and expect either an option, a separator,
        # or the start of positionals
        case "$1" in
        -) break ;; # positional
        --) shift; break ;; # separator
        --*) opt="$1"; shift ;; # long option
        -*) opt="${1:0:2}"; opt_group="${1:2}"; shift ;; # short option
        *) break ;; # positional
        esac
        # lookup opt_var and opt_arity
        local candidates=("${patterns[@]}")
        while (( ${#candidates[@]} )); do
            if [[ "$opt" == "${candidates[0]}" ]]; then
                opt_var="${candidates[1]}"
                opt_arity="${candidates[2]}"
                # if arity was omitted and we are using garbage data,
                # don't do that
                case "$opt_arity" in
                :*) : ;;
                *) opt_arity='' ;;
                esac
                break
            fi
            shift-var candidates
        done
        # check for bad option
        assert test "$opt_var" `
            `--or-else "Unknown option '$opt'. "`
                `"Try $(pack-words "$0") --help"
        # if we have a group, we need to deal with it
        if [[ "$opt_group" ]]; then
            # check if the arity accepts the rest of the group
            case "$(check-arity "$opt_arity" "$opt_group")" in
            # if it does, unshift the group as an argument
            argument) set -- "$opt_group" "$@" ;;
            # otherwise, unshift the group as an option group
            *) set -- "-$opt_group" "$@" ;;
            esac
            opt_group=''
        fi
        # parse opt args
        unpack-words + "$order_var" $(pack-words "$opt_var")
        while true; do
            local arg="$1"
            # if no more args, insert implicit separator
            if ! (( $# )); then
                arg=--
            fi
            local check="$(check-arity "$opt_arity" "${opt_args[@]}" "$arg")"
            case "$check" in
            # if it's an argument, append it tentatively
            argument) opt_args+=("$arg"); shift ;;
            # otherwise, we know we are stopping no matter what,
            # so append all arguments permanently;
            # then, check again for further processing
            *)  unpack-words + "$opt_var" $(pack-words "${opt_args[@]}" --)
                case "$check" in
                # separator: consume, next option
                separator) shift; break ;;
                # option: don't consume, next option
                option) break ;;
                # positional: don't consume, no more options possible
                positional) break 2 ;;
                # report errors
                error-insufficient)
                    assert false --or-else `
                        `"Too few arguments to option '$opt'. "`
                        `"Try $(pack-words "$0") --help" ;;
                error-excessive)
                    assert false --or-else `
                        `"Internal cc-scvc-cb3l library error: "`
                        `"too many arguments to option '$opt'; "`
                        `"because of the way parse-opts "`
                        `"is supposed to work, this should be impossible." ;;
                *)  assert false --or-else `
                        `"Internal cc-scvc-cb3l library error: "`
                        `"stage-1 arity check produced an invalid value "`
                        `"($check).";;
                esac ;;
            esac
        done
    done
    # we should be done parsing at this point;
    # rest of args should be positionals
    unpack-words "$posn_var" $(pack-words "$@")
}
unit-test:parse-opts() {
    parse-opts `
        `order `
        `-a a -b b : -c c :: `
        `--de de :2-4 --fg fg :3-5 --hi hi :+o `
        `posns -- `
        `-c6 -abc --fg 1 2 3 --hi abc --def -- --de 4 5 6 --fg 7 8 9 -- x y z
    assert test "${order[*]}" = 'c a b fg hi de fg'
    assert test "${a[*]}" = '--'
    assert test "${b[*]}" = 'c --'
    assert test "${c[*]}" = '6 --'
    assert test "${de[*]}" = '4 5 6 --'
    assert test "${fg[*]}" = '1 2 3 -- 7 8 9 --'
    assert test "${hi[*]}" = 'abc --def --'
    assert test "${posns[*]}" = 'x y z'
}

# subst [PATTERN REPLACEMENT] ...
# In each line of input, replaces text matching glob PATTERN with REPLACEMENT
# using bash built-in replacement in variable expansion.
# Result may depend on order of PATTERNs;
# later PATTERNs can match and overwrite parts of prior REPLACEMENTs.
# Exits with success if any substitution was made or failure otherwise.
subst() {
    # read args and init vars
    local line new_line any_subst=''
    local patterns=()
    local replacements=()
    local index
    while (( $# )); do
        patterns+=("$1")
        shift
        replacements+=("$1")
        shift
    done
    # iterate lines of input
    while read line; do
        # sub-iterate pattern and replacement arrays in lockstep
        for (( index=0; index < ${#patterns[@]}; index++ )); do
            # in line, replace pattern with replacement
            new_line="${line//${patterns[$index]}/${replacements[$index]}}"
            # take note if there was a change before updating line
            if [[ "$line" != "$new_line" ]]; then
                any_subst=:
            fi
            line="$new_line"
        done
        echo "$line"
    done
    # succeed iff there was a change
    [[ "$any_subst" ]]
}
unit-test:subst() {
    assert test "$(subst %a b %b c %c a <<< '%a %b %c')" = 'b c a'
}

# asubst [PATTERN REPLACEMENT ... --] ... VAR
# Like subst, but for a replacement to occur, PATTERN must match a whole word,
# and the word is replaced with arbitrarily many REPLACEMENT words.
# Additionally, such that this notion has any meaning, input is not read,
# nor output produced; instead, VAR, which should be an array variable,
# serves as both input and output. As with subst, result may depend
# on order of PATTERNs. Also as with subst, exits with success
# if any substitution was made or failure otherwise.
asubst() {
    # init vars; last arg is the var we are working on
    local pattern replacement=() var="${@:$#}[@]" any_subst=''
    local array=("${!var}") old_array=("${!var}") temp_array=() word index
    # iterate args
    while (( $# > 1 )); do
        # first of each sublist is the pattern, read replacement up to --
        pattern="$1"
        replacement=()
        shift
        while (( $# > 1 )); do
            if [[ "$1" == -- ]]; then
                shift
                break
            else
                replacement+=("$1")
                shift
            fi
        done
        # sub-iterate array and rebuild it in a separate buffer,
        # performing substitutions as we go
        temp_array=()
        for word in "${array[@]}"; do
            case "$word" in
            $pattern) temp_array+=("${replacement[@]}") ;;
            *) temp_array+=("$word") ;;
            esac
        done
        # commit the separate buffer to the original array
        array=("${temp_array[@]}")
    done
    # commit our "original array" -- itself a separate buffer,
    # to avoid the ugliness of array indirection as much as possible --
    # back to the input variable
    unpack-words "${var%\[@\]}" $(pack-words "${array[@]}")
    # assess changes, succeed iff there were any
    if (( ${#array[@]} != ${#old_array[@]} )); then
        # different length = change
        return 0
    else
        for (( index=0; index < ${#array[@]}; index++ )); do
            if [[ "${array[$index]}" != "${old_array[$index]}" ]]; then
                # any different words = change
                return 0
            fi
        done
        # same length and words = no change
        return 1
    fi
}

# asubst-do [PATTERN REPLACEMENT ... --] ... COMMAND ...
# Creates a temporary local array from multiword COMMAND,
# asubst's it using PATTERNs and REPLACEMENTs, and runs it as a command.
asubst-do() {
    # Split options into last group and all leading groups
    local word command=() asubst_args=()
    for word in "$@"; do
        if [[ "$word" == -- ]]; then
            asubst_args+=("${command[@]}")
            command=()
        else
            command+=("$word")
        fi
        shift
    done
    # Do asubst and run command
    asubst "${asubst_args[@]}" command
    "${command[@]}"
}

# rsubst [PATTERN VARIABLE] ...
# In each VARIABLE, repeatedly substs the contents of each other VARIABLE
# for its respective PATTERN. Returns when every subst in a round fails.
# To request a VARIABLE be updated but avoid making its value available
# under any PATTERN, use an empty string for its PATTERN.
# If a VARIABLE ends with [@], it is presumed an array variable,
# and treated differently: to write to it, asubst is used instead of subst;
# it is also read as an array, a distinction mostly only meaningful
# when writing an array to part of another array.
rsubst() {
    # read args and init vars
    local any_subst=:
    local patterns=()
    local variables=()
    local subst_args=()
    local subst_output subst_status indirect index index2 is_array
    while (( $# )); do
        patterns+=("$1")
        shift
        variables+=("$1")
        shift
    done
    # repeat while last iteration introduced any changes
    while [[ "$any_subst" ]]; do
        any_subst='' # <-- this one has not yet, it just started
        # iterate vars; the var at $index is the one we're modifying
        for (( index=0; index < ${#variables[@]}; index++ )); do
            # awful evil array indirection; in the meantime,
            # check if we actually do have an array
            indirect="${variables[$index]}"
            is_array=''
            if [[ "${indirect%\[@\]}" != "$indirect" ]]; then
                is_array=:
            fi
            # sub-iterate vars; the var at each $index2 is used
            # as information to help modify the var at $index
            subst_args=()
            for (( index2=0; index2 < ${#variables[@]}; index2++ )); do
                # don't bother with subst on a var against itself
                # and also don't subst on any empty patterns
                if (( index != index2 )) && [[ "${patterns[$index2]}" ]]; then
                    # even more array indirection.
                    # I am beginning to think
                    # I should have started this library off
                    # by providing better and more uniform ways
                    # to deal with atoms, arrays, and indirection in general
                    indirect="${variables[$index2]}"
                    subst_arg=("${!indirect}")
                    subst_args+=("${patterns[$index2]}" "${subst_arg[@]}")
                    # if we will be using asubst,
                    # arg sub-lists must be terminated
                    if [[ "$is_array" ]]; then
                        subst_args+=(--)
                    fi
                fi
            done
            # use asubst if we are writing back to an array,
            # just subst otherwise
            if [[ "$is_array" ]]; then
                asubst "${subst_args[@]}" "${variables[$index]%\[@\]}"
                subst_status=$?
            else
                indirect="${variables[$index]}"
                subst_output="$(subst "${subst_args[@]}" <<< "${!indirect}")"
                subst_status=$?
                eval "$indirect=$(printf '%q' "$subst_output")"
            fi
            # take note if any change was made (subst/asubst will tell us)
            if ! (( $subst_status )); then
                any_subst=:
            fi
        done
    done
}
unit-test:rsubst() {
    a='%b'
    b='%c'
    c='%d'
    d='e'
    rsubst '' a %b b %c c %d d
    assert test "$a" = e -a "$b" = e -a "$c" = e -a "$d" = e
}

# rsubst-do [PATTERN VAR] ... -- COMMAND ...
# First does an rsubst, and then an asubst-do, but before the asubst-do,
# replaces each VAR with its contents and a --, of course.
# Requires same [@] suffix notation as rsubst.
rsubst-do() {
    local rsubst_args=() patterns=() vars=() asubst_do_args=()
    local template=() command=()
    local var index
    while (( $# )); do
        if [[ "$1" == -- ]]; then
            shift
            break
        else
            patterns+=("$1")
            rsubst_args+=("$1")
            shift
            if [[ "$1" != -- ]]; then
                vars+=("$1")
                rsubst_args+=("$1")
                shift
            fi
        fi
    done
    template=("$@")
    rsubst "${rsubst_args[@]}"
    # TODO
}

# split-word SEP ARG
# Splits ARG on glob pattern SEP.
split-word() {
    local sep="$1" arg="$2" head out=()
    while true; do
        head="${arg%%${sep}*}"
        out+=("$head")
        if [[ "$head" == "$arg" ]]; then
            break
        else
            arg="${arg#*${sep}}"
        fi
    done
    echo "${out[@]}"
}
unit-test:split-word() {
    assert test "$(split-word - 'a-b-c d-e f')" = 'a b c d e f'
}

# join-words SEP ARG ...
# Joins ARGs on literal string SEP.
join-words() {
    local sep="$1"
    shift
    if (( $# )); then
        printf %s "$1"
        shift
        while (( $# )); do
            printf %s "${sep}$1"
            shift
        done
        echo
    fi
}
unit-test:join-words() {
    assert test "$(join-words - a b 'c d' e f)" = 'a-b-c d-e-f'
}

# read-to-array [+] VAR
# Like mapfile -t from future bash versions.
# If + is given, appends instead of setting.
read-to-array() {
    if [[ "$1" == '+' ]]; then
        shift
    else
        unpack-words "$@"
    fi
    local line
    while read line; do
        unpack-words + "$@" $(pack-words "$line")
    done
}
unit-test:read-to-array() {
    array=()
    read-to-array array << EOT
        a
        b
        c d
        e f
EOT
    assert --eval "(( ${#array[@]} == 4 ))"
    assert test "${array[3]}" = 'e f'
}

# ==============================
# ssh and secure temporary files
# ==============================

# secure-delete FILE ...
# Overwrites each FILE with data from /dev/urandom and then deletes it.
# If FILE is a directory, uses find to secure-delete each regular file
# in the directory.
secure-delete() {
    local file subfile wc
    for file in "$@"; do
        if [[ -d "$file" ]]; then
            while read subfile; do
                secure-delete "$subfile"
            done < <(find "$file" -type f)
        elif [[ -f "$file" ]]; then
            wc=($(wc -c "$file")) # word-splitting on purpose
            log -v "Randoming-out $file."
            head -c$wc /dev/urandom > "$file"
        fi
        if [[ -e "$file" ]]; then
            log -v "Deleting $file."
            rm -rf "$file"
        fi
    done
}

# delete-rundir
# Randoms-out and deletes $RUNDIR if it exists.
delete-rundir() {
    if [[ "$RUNDIR" && -d "$RUNDIR" ]]; then
        secure-delete "$RUNDIR"
        RUNDIR=''
    fi
}

# ensure-rundir
# If $RUNDIR does not exist, creates a rundir and assigns RUNDIR accordingly,
# and schedules $RUNDIR to be deleted at exit.
ensure-rundir() {
    if [[ ! ( "$RUNDIR" && -d "$RUNDIR" ) ]]; then
        at-exit delete-rundir
        RUNDIR="$(
            umask 0077
            mktemp -d "${TMPDIR:-$HOME}"`
                `"/${CALLING_CONTEXT_SHELL_NAME:-$(basename "$0")}.d.XXXXXX"
        )"
        assert test -d "$RUNDIR" --or-else `
            `"Could not create rundir at $RUNDIR."
        log -o "Created rundir at $RUNDIR."
    fi
}

# ensure-kill [-t SECONDS] [-s SIGNAL] PID
# Tries to stop PID gracefully by sending SIGNAL (default TERM).
# If PID does not stop in SECONDS (default 10), stops PID by sending KILL.
# I recognize this would normally be bad practice,
# and am implementing it here anyway, because occasionally --
# and some of the work this library is meant for includes such occasions --
# it is more important, e.g. for security reasons, to ensure a process stops
# than to protect the integrity of whatever data it may be writing.
# The system's sleep implementation must support non-integers,
# as centisecond sleeps are used to spin-wait on the process.
ensure-kill() {
    local order=() seconds=() signal=() pid=() target
    parse-opts order `
        `-t seconds : --timeout seconds : `
        `-s signal : --signal signal : `
        `pid `
        `-- "$@"
    target=$(($(date +%s) + ${seconds:-10}))
    log -v "Sending signal ${signal:-TERM} to PID $pid."
    kill -"${signal:-TERM}" "$pid"
    log -v "Waiting for PID $pid to stop..."
    while (( $(date +%s) < target )); do
        if ps -p "$pid" > /dev/null 2>&1; then
            sleep 0.01
        else
            log -o "PID $pid stopped."
            return 0
        fi
    done
    kill -KILL "$pid"
    log -w "PID $pid did not comply with signal ${signal:-TERM} "`
        `"for ${seconds:-10} seconds; had to send it KILL."
}

# stop-ssh-executor [-t SECONDS] [-s SIGNAL] [NAME]
# Stops sshd process started by start-ssh-executor.
# If no NAME is given, attempts to stop every ssh executor
# that may have started, by inspecting $RUNDIR/ssh-executors.
stop-ssh-executor() {
    local order=() seconds=() signal=() name=() dir
    parse-opts order `
        `-t seconds : --timeout seconds : `
        `-s signal : --signal signal : `
        `name `
        `-- "$@"
    if (( ${#name[@]} )); then
        dir="$RUNDIR/ssh-executors/$name"
        if [[ -d "$dir" && -f "$dir/sshd_pid" ]]; then
            ensure-kill `
                `-t "${seconds:-10}" `
                `-s "${signal:-TERM}" `
                `"$(cat "$dir/sshd_pid")"
        fi
    else
        for dir in "$RUNDIR/ssh-executors"/*; do
            stop-ssh-executor "$@" "$(basename "$dir")"
        done
    fi
}

# start-ssh-executor [-p PORT] [-x ADDRESS] [-f] NAME COMMAND
# Starts and backgrounds an unprivileged and restrictive sshd instance
# on port PORT (default 8022) with ForceCommand set to COMMAND.
# Only login as the invoking user is allowed.
# Two random non-passphrase-protected keypairs are generated:
# one as a host keypair, and one to be authorized for outside access.
# (Since the host keypair is randomly generated ad-hoc,
# non-interactive clients must connect with StrictHostKeyChecking=no,
# as it is guaranteed the client will not already know the host.)
# All files the process requires are stored in $RUNDIR/ssh-executors/NAME/.
# If -x is given, connections are e[x]pected to come from ADDRESS,
# and any other addresses are turned away.
# If -f is given, sftp is allowed, and uses the same COMMAND;
# otherwise, no subsystem is defined for it, and so it is de-facto forbidden.
start-ssh-executor() {
    at-exit stop-ssh-executor
    local order=() port=() address=() posns=() sftp_allowed=()
    parse-opts order `
        `-p port : --port port : `
        `-x address : --expect address : `
        `-f sftp_allowed --sftp-ok sftp_allowed `
        `posns `
        `-- "$@"
    local name="${posns[0]}" command="${posns[*]:1}"
    assert test "$name" -a "$command" `
        `--or-else "Too few arguments to start-ssh-executor."
    log -v "Setting up ssh executor '$name'..."
    # create directory
    ensure-rundir
    local dir="$RUNDIR/ssh-executors/$name"
    assert mkdir -p "$dir" `
        `--or-else "Could not create directory $dir."
    log -o "Created directory $dir."
    # create keys
    assert ssh-keygen -f "$dir/host_key" -t rsa -N '' `
        `--or-else "Could not create host key pair in $dir."
    assert ssh-keygen -f "$dir/client_key" -t rsa -N '' `
        `--or-else "Could not create client key pair in $dir."
    assert cp "$dir/client_key.pub" "$dir/authorized_keys" `
        `--or-else "Could not create authorized_keys in $dir "`
            `"from client pubkey."
    log -o "Created host key pair, client key pair, and authorized_keys "`
        `"in $dir."
    # create port file for use by ssh-2way
    echo "${port:-8022}" > "$dir/sshd_port"
    # setup config
    cat > "$dir/sshd_config" << EOT
        Port ${port:-8022}
        ForceCommand $command
        AllowTCPForwarding no
        X11Forwarding no
        PermitTTY no
        UsePAM yes
        ChallengeResponseAuthentication no
        PasswordAuthentication no
        PubkeyAuthentication yes
        PidFile none
        HostKey "$dir/host_key"
        AuthorizedKeysFile "$dir/authorized_keys"
EOT
    if [[ "$address" ]]; then cat >> "$dir/sshd_config" << EOT
        DenyUsers *
        Match Host $address
            AllowUsers $USER
EOT
    fi
    if [[ "$sftp_allowed" ]]; then cat >> "$dir/sshd_config" << EOT
        Subsystem sftp $command
EOT
    fi
    assert test -f "$dir/sshd_config" `
        `--or-else "Could not create sshd_config in $dir."
    log -o "Created sshd_config in $dir."
    # start sshd
    assert --eval "$(command -v sshd) "`
        `"-o 'LogLevel=DEBUG3' "`
        `"-Def '$dir/sshd_config' >'$dir/sshd_log' 2>&1 "`
        `"& echo "'$!'" > '$dir/sshd_pid'" `
        `--or-else "Could not start sshd."
    log -o "Started sshd for ssh executor '$name'."
}

# start-sftp-executor [-p PORT] [-x ADDRESS] NAME DIR
# Equivalent to start-ssh-executor with COMMAND given
# as internal-sftp -e -d DIR.
start-sftp-executor() {
    ensure-rundir
    assert --eval "(( $# >= 2 ))" `
        `--or-else "Too few arguments to start-sftp-executor."
    local name="${@:1:$(($#-1))}" dir="${@:$#}"
    assert mkdir -p "$dir" `
        `--or-else "Could not create directory $dir."
    start-ssh-executor -f "$name" internal-sftp -e -d "$dir"
}

# ssh-do-script ARG ... 3< SCRIPT
# Forwards ARGs to ssh. If a connection can be established,
# remotely executes SCRIPT in a prepared environment,
# in which this library is loaded and usable by SCRIPT.
# Expects SCRIPT to be provided on fd 3.
# (Stdin is reserved for interactive auth.)
#
# Remote LOG_LEVEL matches that of the calling machine,
# and remote CALLING_CONTEXT_SHELL_NAME matches the last ARG,
# which is assumed to be, and should be, the name or address used
# to connect to the remote host.
#
# Do not specify a remote command in ARGs.
# The remote command will be bash -s.
# If you need a different remote command, put it in SCRIPT.
#
# This library is sent and loaded twice: once inline,
# to bootstrap the library to allow logging and rundir operations,
# and once as a heredoc redirected to a file,
# so that the library knows its file path on remote,
# and can operate on itself if desired
# (e.g. install, cc-scvc-cb3l-path, etc).
ssh-do-script() {
    assert --eval "(( $# > 0 ))"
    # Pregenerate log messages for the remote host
    # to display before it knows about our logging system yet
    local old_shell_name="$CALLING_CONTEXT_SHELL_NAME"
    CALLING_CONTEXT_SHELL_NAME="${@:$#}"
    local connected_message=`
        `"$(log-pregen -o 'Connected.')"
    local loading_message=`
        `"$(log-pregen -v 'Preloading library to create rundir.' 2>&1)"
    CALLING_CONTEXT_SHELL_NAME="$old_shell_name"
    # To guarantee our EOT token for transferring the library
    # does not appear in the library itself at the left margin,
    # we must use a variable here, and dereference it in the heredoc.
    # Otherwise, the library would be truncated on transfer.
    local library_eot_token=EOT_DOES_NOT_APPEAR_IN_LIBRARY_AT_LEFT_MARGIN
    log -v "Attempting to connect to ${@:$#}..."
    ssh "$@" bash -s << EOT
        if [[ "$connected_message" ]]; then
            echo>&2 "$connected_message"
        fi
        if [[ "$loading_message" ]]; then
            echo>&2 "$loading_message"
        fi
        $(cat "$(cc-scvc-cb3l-path)")
        ensure-rundir
        CALLING_CONTEXT_SHELL_NAME="${@:$#}"
        LOG_LEVEL="$LOG_LEVEL"
        log -v "Redownloading library into rundir."
        cat > "\$RUNDIR/cc-scvc-cb3l.sh" << '$library_eot_token'
$(cat "$(cc-scvc-cb3l-path)")
$library_eot_token
        log -o "Environment prepared."
        $(cat<&3)
EOT
}

# ssh-2way NAME ARG ... 3< SCRIPT
# To be run after start-ssh-executor has been called with the same NAME.
# Expects SCRIPT to be provided on fd 3.
# (Stdin is reserved for interactive auth.)
#
# Wraps ssh-do-script to provide additional variables:
#   SSH_REPLY_ADDR      First field of $SSH_CLIENT in remote session
#   SSH_REPLY_PORT      Port used by ssh executor NAME on original machine
#   SSH_REPLY_USER      User running this script on original machine
#   SSH_REPLY_KEY       Path to recevied private key in remote session.
#   SSH_REPLY_PUBKEY    Path to received public key in remote session.
# As implied by the last few of these variables,
# the client_key and client_key.pub created for ssh executor NAME
# are also transferred into the remote machine's rundir.
#
# All of this data is transferred to allow SCRIPT on the remote machine
# to make a return connection to the local machine's ssh executor NAME.
# This return connection can be facilitated by ssh-reply.
ssh-2way() {
    # check existence of needed files
    local name="$1"
    local dir="$RUNDIR/ssh-executors/$name"
    assert test -d "$dir" --or-else "Directory $dir does not exist."
    local file
    for file in `
        `"$dir/sshd_port" `
        `"$dir/client_key" `
        `"$dir/client_key.pub"
    do
        assert test -f "$file" --or-else "Missing $file."
    done
    # modified ssh-do-script w/ SSH_REPLY_* vars
    ssh-do-script "${@:2}" 3<< EOT
        log -v "Receiving reply stamp."
        SSH_REPLY_ADDR="\$(cut -d' ' -f1 <<< "\$SSH_CLIENT")"
        SSH_REPLY_PORT="$(cat "$dir/sshd_port")"
        SSH_REPLY_USER="$USER"
        SSH_REPLY_KEY=`
            `"\$RUNDIR/remote-ssh-executors/$name/client_key"
        SSH_REPLY_PUBKEY=`
            `"\$RUNDIR/remote-ssh-executors/$name/client_key.pub"
        log -v "Receiving keys."
        assert mkdir -p "\$RUNDIR/remote-ssh-executors/$name" `
            `--or-else "Failed to create dir to receive keys."
        ( # <-- subshell to prevent leaking umask change
            umask 0077
            cat > "\$SSH_REPLY_KEY" << 'EOT_VERY_UNLIKELY_TO_APPEAR_IN_KEY'
$(cat "$dir/client_key")
EOT_VERY_UNLIKELY_TO_APPEAR_IN_KEY
        )
        cat > "\$SSH_REPLY_PUBKEY" << 'EOT_VERY_UNLIKELY_TO_APPEAR_IN_KEY'
$(cat "$dir/client_key.pub")
EOT_VERY_UNLIKELY_TO_APPEAR_IN_KEY
        log -o "Reply stamp prepared."
        $(cat<&3)
EOT
}

# ssh-reply ARG ...
# To be run within a script executed remotely by ssh-2way.
# Sends a reply such that SSH_ORIGINAL_COMMAND is ARG ... .
# (Since ssh executors use ForceCommand, it is not necessarily likely
# that ARG ... should be a command of some kind,
# despite it winding up assigned to SSH_ORIGINAL_COMMAND.)
ssh-reply() {
    log -v "Sending reply to ssh executor."
    ssh -o 'StrictHostKeyChecking=no' `
        `-o 'UserKnownHostsFile=/dev/null' `
        `-p "$SSH_REPLY_PORT" `
        `-i "$SSH_REPLY_KEY" `
        `"$SSH_REPLY_USER@$SSH_REPLY_ADDR" `
        `"$@"
}

# sftp-single-command OUTER_COMMAND ARG ... -- INNER_COMMAND ARG ...
# Forms an sftp connection with OUTER_COMMAND
# and runs INNER_COMMAND in the resulting sftp shell.
sftp-single-command() {
    local outer=()
    while (( $# )); do
        if [[ "$1" == -- ]]; then
            shift
            break
        else
            outer+=("$1")
            shift
        fi
    done
    sftp "${outer[@]}" <<< "$(pack-words "$@")"
}

# sftp-reply COMMAND ARG ...
# To be run within a script executed remotely by ssh-2way
# with respect to an ssh executor created with start-sftp-executor.
# Executes sftp command COMMAND ARG ... .
sftp-reply() {
    log -v "Sending reply to sftp executor."
    sftp-single-command -a -f -r `
        `-o 'StrictHostKeyChecking=no' `
        `-o 'UserKnownHostsFile=/dev/null' `
        `-P "$SSH_REPLY_PORT" `
        `-i "$SSH_REPLY_KEY" `
        `"$SSH_REPLY_USER@$SSH_REPLY_ADDR"`
        ` -- "$@"
}

# ===============================
# Effective entry point of script
# ===============================

# self-install [--env-name ENV_NAME] [--default DEFAULT_DIR] [DIR]
# Installs calling script to given DIR,
# or DEFAULT_DIR if no DIR is given,
# or /usr/local/bin if no DEFAULT_DIR is given.
# If both a DIR and an ENV_NAME are given,
# logs a message recommending the caller edit their shell profile
# and set the variable named by ENV_NAME to the value they gave as DIR.
# Otherwise, ENV_NAME has no effect.
self-install() {
    # parse opts
    local default_dir=() env_name=() opt_order=() dir=()
    parse-opts opt_order `
        `--env-name env_name `
        `--default default_dir `
        `dir -- "$@"
    default_dir=("${default_dir:-/usr/local/bin}")
    local dest="${dir:-$default_dir}/$(basename "$0")"
    local src="$0"
    if [[ "$0" == "$BASH_SOURCE" && ! ( "$0" && -f "$0" && -r "$0" ) ]]; then
        src="$(cc-scvc-cb3l-path)"
    fi
    # ensure we can access ourself
    assert test "$src" -a -f "$src" -a -r "$src" `
        `--or-else "The script cannot find itself. "`
            `"You might be in a descendant or remote bash session "`
            `"that sourced this script over a stream "`
            `"that was not a regular file (such as stdin). "`
            `"You should only call self-install "`
            `"either from within a script on-disk "`
            `"that has a self to install, "`
            `"or indirectly by running (not sourcing) such a script."
    # try to create directory
    assert mkdir -p "$(dirname "$dest")" `
        `--or-else "Cannot create destination directory for install. "`
            `"(Check permissions on parent directory "`
            `"and/or try again with root privileges.)"
    # try to install
    assert cp "$src" "$dest" `
        `--or-else "Cannot copy script to install destination. "`
            `"(Check permissions on parent directory "`
            `"and/or try again with root privileges.)"
    # try to make executable
    assert chmod 0755 "$dest" `
        `--or-else "Cannot make installed script executable. "`
            `"(Check filesystem type and mount options.)"
    # check install
    assert test -f "$dest" -a -x "$dest" `
        `--or-else "Unknown install error."
    # check whether to inform about profile
    if [[ "$env_name" && "$dir" ]]; then
        # Promote success message to notice in this case
        # so the following recommendation is not mistaken for an error
        log "Successfully installed to $dest."
        log "It is recommended to add the following line "`
            `"to ~/.profile, ~/.bash_profile, etc, "`
            `"so that scripts which depend on this script can find it:"
        log "$env_name=$(pack-words "$dir")"
    else
        log -o "Successfully installed to $dest."
    fi
}

# cc-scvc-cb3l-behavior-when-not-sourced ARG ...
# Self-explanatory.
cc-scvc-cb3l-behavior-when-not-sourced() {
    case "$1" in
    --test) test-shell ;;
    --install) self-install `
        `--env-name CC_SCVC_CB3L `
        `--default /usr/local/libexec `
        `"${@:2}" ;;
    *) cc-scvc-cb3l-usage ;;
    esac
}

if [[ "$0" == "$(cc-scvc-cb3l-path)" ]]; then
    cc-scvc-cb3l-behavior-when-not-sourced "$@"
fi
