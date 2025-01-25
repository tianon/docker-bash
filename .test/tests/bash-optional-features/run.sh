#!/usr/bin/env bash
set -Eeuo pipefail

# there's a lot of commands we expect Bash to have, but that it might not due to compilation quirks
# see https://github.com/tianon/docker-bash/pull/45
# and https://www.gnu.org/software/bash/manual/html_node/Optional-Features.html#:~:text=unless%20the%20operating%20system%20does%20not%20provide%20the%20necessary%20support

image="$1"

args=( --rm --interactive )
if [ -t 0 ] && [ -t 1 ]; then
	args+=( --tty )
fi

docker run "${args[@]}" "$image" -Eeuo pipefail -xc '
	# --enable-array-variables 😏
	cmds=(
		# --enable-alias
		alias unalias
		# --enable-command-timing
		time
		# --enable-cond-command
		"[["
		# --enable-directory-stack
		pushd popd dirs
		# --enable-disabled-builtins
		builtin enable
		# --enable-help-builtin
		help
		# --enable-history
		fc history
		# --enable-job-control
		bg fg jobs kill wait disown suspend
		# --enable-progcomp
		complete
		# --enable-select
		select
	)
	if [ "${BASH_VERSINFO:-0}" -ge 4 ]; then
		# Bash 3.0 does not support arr+=( ... ) and balks at this syntax even in an optional block 😂
		cmds=( "${cmds[@]}"
			# --enable-coprocesses
			coproc
		)
	fi
	for cmd in "${cmds[@]}"; do
		PATH= command -v "$cmd"
	done
'
