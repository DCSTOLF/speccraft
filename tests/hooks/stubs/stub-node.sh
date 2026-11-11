#!/usr/bin/env sh
# Spec 0054 T1 — a stand-in for `node` when driving the Codex companion.
#
# The adapter always shells out as:
#   node <root>/scripts/codex-companion.mjs <subcommand> [args...]
# so this script is dropped on PATH as `node` and dispatches on $2. The real
# companion is never run: these tests must pass with no Codex plugin, no
# ChatGPT auth and no network. T1's live smoke (AC26/26a) is the only thing
# that talks to the real one, and it is gated behind SPECCRAFT_LIVE_CODEX_SMOKE.
#
# Every payload shape here was read out of the installed 1.0.6 source, not
# guessed. See fixtures/review-dispatch/codex/INTERFACE-1.0.6.md for the line
# references and for the two same-named `status` fields at different depths.
#
# This file lives in stubs/ rather than fixtures/ on purpose. The sweep in
# tests-portability-sweep.bats exempts fixtures/ because a fixture is inert
# data that is never executed, and states the boundary explicitly: "a fixture
# that ever needs to be executed must be moved out of fixtures/, at which point
# the sweep sees it again." This script IS executed — it is dropped on PATH as
# `node` — so leaving it under fixtures/ would hide a GNU-only form in it from
# the macOS runner. Hence POSIX sh only, and hence this directory.
#
# Knobs (all optional):
#   STUB_CODEX_FIXTURE_DIR    where the JSON/usage fixtures live (default: the
#                             review-dispatch/codex fixtures dir next door)
#   STUB_CODEX_ARGV_LOG       append one space-joined argv line per invocation
#   STUB_CODEX_STATE_DIR      where the poll counter lives (default: alongside the log)
#   STUB_CODEX_READY          0 => setup reports ready:false (default 1)
#   STUB_CODEX_NOT_READY_WHY  reason text when ready:false
#   STUB_CODEX_NOT_READY_ROOTS
#                             colon-separated plugin roots whose `setup` answers
#                             ready:false regardless of STUB_CODEX_READY. AC5c
#                             needs one root ready and another not in the SAME
#                             round, to prove readiness is never assumed across
#                             roots; a single global flag cannot express that.
#   STUB_CODEX_SETUP_RAW      literal text `setup` prints instead of JSON, for
#                             the unparseable-output row
#   STUB_CODEX_EXPECT_PROMPT_FILE
#                             path the `task` --prompt-file argument must be
#                             INODE-EQUAL to. Compared with `test -ef`, never
#                             by shelling out to stat with its GNU-only format
#                             flag, which the portability sweep flags on sight.
#                             Proves the round artifact itself was handed over
#                             rather than a copy of it; a mismatch exits 65.
#   STUB_CODEX_JOB_ID         job id handed back by `task --background`
#   STUB_CODEX_STATUS_SEQUENCE
#                             space-separated job statuses, consumed one per
#                             `status` call; the last one repeats forever.
#                             Default "completed" (terminal on the first poll).
#   STUB_CODEX_RESULT_FILE    JSON `result <id> --json` prints (default: the
#                             task-success-1.0.6.json fixture beside this file)
#   STUB_CODEX_CANCEL_CONFIRMS
#                             0 => `cancel` succeeds but the confirming
#                             `status` still reports running, which is the
#                             codex-cancel-unconfirmed path
#   STUB_CODEX_EXIT           forced exit code, applied after printing
#
# Deliberately no `sed` (spec 0049 removed it from the command libs) and no
# bashisms: this runs under whatever /bin/sh the host provides.

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
fixtures=${STUB_CODEX_FIXTURE_DIR:-$here/../fixtures/review-dispatch/codex}

if [ -n "${STUB_CODEX_ARGV_LOG:-}" ]; then
	# "$*" is the whole argv space-joined, which is what AC6's argv assertion
	# greps for as one exact line.
	printf '%s\n' "$*" >>"$STUB_CODEX_ARGV_LOG"
fi

state_dir=${STUB_CODEX_STATE_DIR:-}
if [ -z "$state_dir" ]; then
	if [ -n "${STUB_CODEX_ARGV_LOG:-}" ]; then
		state_dir=$(dirname -- "$STUB_CODEX_ARGV_LOG")
	else
		state_dir=${TMPDIR:-/tmp}
	fi
fi

job_id=${STUB_CODEX_JOB_ID:-task-mhqk3x2p-a7f2kd}

# `node --version` is a capability probe, not a companion call, so it is
# answered before the argv is interpreted as a subcommand.
case ${1:-} in
--version | -v)
	printf 'v20.20.2\n'
	exit "${STUB_CODEX_EXIT:-0}"
	;;
esac

# $1 is the companion script path; the subcommand is $2.
subcommand=${2:-help}

# next_status pops the next entry off STUB_CODEX_STATUS_SEQUENCE, remembering
# how many polls have happened. The final entry repeats, so a sequence of
# "running completed" answers every later poll "completed" rather than running
# off the end of the list.
next_status() {
	count_file="$state_dir/stub-codex-status-count"
	n=0
	if [ -f "$count_file" ]; then
		n=$(cat "$count_file")
	fi
	echo $((n + 1)) >"$count_file"

	# shellcheck disable=SC2086 # deliberate word splitting into positionals
	set -- ${STUB_CODEX_STATUS_SEQUENCE:-completed}
	[ "$#" -gt 0 ] || set -- completed
	while [ "$n" -gt 0 ] && [ "$#" -gt 1 ]; do
		shift
		n=$((n - 1))
	done
	printf '%s' "$1"
}

case $subcommand in
help | --help)
	cat -- "$fixtures/printusage-1.0.6.txt"
	;;

setup)
	if [ -n "${STUB_CODEX_SETUP_RAW:-}" ]; then
		printf '%s\n' "$STUB_CODEX_SETUP_RAW"
		exit "${STUB_CODEX_EXIT:-0}"
	fi

	# Per-root readiness. $1 is the companion script path, so the root is its
	# grandparent; matching on the path prefix lets one round hold a ready root
	# and an unready one at the same time.
	ready_for_this_root=${STUB_CODEX_READY:-1}
	if [ -n "${STUB_CODEX_NOT_READY_ROOTS:-}" ]; then
		_ifs_saved=$IFS
		IFS=':'
		for _nr in $STUB_CODEX_NOT_READY_ROOTS; do
			[ -n "$_nr" ] || continue
			case $1 in
			"$_nr"/*) ready_for_this_root=0 ;;
			esac
		done
		IFS=$_ifs_saved
	fi

	if [ "$ready_for_this_root" = "0" ]; then
		why=${STUB_CODEX_NOT_READY_WHY:-codex login required}
		printf '{\n'
		printf '  "ready": false,\n'
		printf '  "node": { "available": true, "version": "v20.20.2" },\n'
		printf '  "codex": { "available": true, "version": "codex-cli 0.145.0" },\n'
		printf '  "auth": { "loggedIn": false, "requiresOpenaiAuth": true },\n'
		printf '  "nextSteps": ["%s"]\n' "$why"
		printf '}\n'
	else
		printf '{\n'
		printf '  "ready": true,\n'
		printf '  "node": { "available": true, "version": "v20.20.2" },\n'
		printf '  "codex": { "available": true, "version": "codex-cli 0.145.0" },\n'
		printf '  "auth": { "loggedIn": true, "requiresOpenaiAuth": true },\n'
		printf '  "nextSteps": []\n'
		printf '}\n'
	fi
	;;

task)
	if [ -n "${STUB_CODEX_EXPECT_PROMPT_FILE:-}" ]; then
		# Pull the value that follows --prompt-file out of the argv.
		_pf=''
		_want_pf=0
		for _a in "$@"; do
			if [ "$_want_pf" = 1 ]; then
				_pf=$_a
				_want_pf=0
				continue
			fi
			[ "$_a" = "--prompt-file" ] && _want_pf=1
		done
		if [ -z "$_pf" ]; then
			printf 'stub-node.sh: task invoked with no --prompt-file\n' >&2
			exit 65
		fi
		# `test -ef` compares device+inode, so a byte-identical COPY fails here.
		if [ ! "$_pf" -ef "$STUB_CODEX_EXPECT_PROMPT_FILE" ]; then
			printf 'stub-node.sh: --prompt-file %s is not the artifact %s\n' \
				"$_pf" "$STUB_CODEX_EXPECT_PROMPT_FILE" >&2
			exit 65
		fi
	fi

	# enqueueBackgroundTask's payload: jobId plus the STRING status "queued".
	printf '{\n'
	printf '  "jobId": "%s",\n' "$job_id"
	printf '  "status": "queued",\n'
	printf '  "title": "speccraft review",\n'
	printf '  "summary": "speccraft review",\n'
	printf '  "logFile": "%s/%s.log"\n' "$state_dir" "$job_id"
	printf '}\n'
	;;

status)
	st=$(next_status)
	if [ "${STUB_CODEX_CANCEL_CONFIRMS:-1}" = "0" ] &&
		[ -f "$state_dir/stub-codex-cancelled" ]; then
		# Cancel was asked for and reported success, yet the job is still
		# going. The adapter must call this codex-cancel-unconfirmed and name
		# the job, never report a plain timeout.
		st=running
	fi
	printf '{\n'
	printf '  "workspaceRoot": "/workspaces/example",\n'
	printf '  "job": {\n'
	printf '    "id": "%s",\n' "$job_id"
	printf '    "status": "%s",\n' "$st"
	printf '    "jobClass": "task",\n'
	printf '    "phase": "%s"\n' "$st"
	printf '  }\n'
	printf '}\n'
	;;

result)
	result_file=${STUB_CODEX_RESULT_FILE:-$fixtures/task-success-1.0.6.json}
	cat -- "$result_file"
	;;

cancel)
	: >"$state_dir/stub-codex-cancelled"
	printf '{\n'
	printf '  "job": { "id": "%s", "status": "cancelled", "phase": "cancelled" },\n' "$job_id"
	printf '  "cancelled": true\n'
	printf '}\n'
	;;

*)
	printf 'stub-node.sh: unhandled companion subcommand %s\n' "$subcommand" >&2
	exit 64
	;;
esac

exit "${STUB_CODEX_EXIT:-0}"
