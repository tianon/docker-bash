#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
	json='{}'
else
	json="$(< versions.json)"
fi
versions=( "${versions[@]%/}" )

ftpBase='ftp://ftp.gnu.org/gnu/bash'
ftp_list() {
	curl --silent --list-only "$ftpBase/${1:-}/"
}

allBaseVersions="$(
	ftp_list \
		| sed -rne '/^bash-([0-9].+)[.]tar[.]gz$/s//\1/p' \
		| sort -V
)"

for version in "${versions[@]}"; do
	export version

	rcVersion="${version%-rc}"
	rcGrepV='-v'
	if [ "$version" != "$rcVersion" ]; then
		rcGrepV=
	fi

	if [ "$version" = 'devel' ]; then
		commit="$(git ls-remote https://git.savannah.gnu.org/git/bash.git refs/heads/devel | cut -d$'\t' -f1)"
		if [ -z "$commit" ]; then
			echo >&2 "error: cannot determine commit for $version (from https://git.savannah.gnu.org/cgit/bash.git)"
			exit 1
		fi
		desc="$(
			curl -fsSL "https://git.savannah.gnu.org/cgit/bash.git/patch/?id=$commit" 2>/dev/null \
				| sed -ne '/^Subject: /{s///p;q}' \
				|| :
		)"
		[ -n "$desc" ]
		timestamp="$(sed -rne '/.*[[:space:]]+bash-([0-9]+)[[:space:]]+.*/s//\1/p' <<<"$desc")"
		[ -n "$timestamp" ]

		echo "$version: $commit ($timestamp)"

		export commit timestamp
		json="$(jq <<<"$json" -c '.[env.version] = {
			version: env.timestamp,
			commit: { version: env.commit },
		}')"
		continue
	fi

	baseline="$(
		grep -E "^$rcVersion([.-]|\$)" <<<"$allBaseVersions" \
			| grep -E $rcGrepV -- '-(rc|beta|alpha)' \
			| tail -1
	)"
	if [ -z "$baseline" ]; then
		echo >&2 "error: cannot find any releases of $version in $ftpBase"
		exit 1
	fi

	patchlevel=
	if [ "$version" = "$rcVersion" ]; then
		patchlevel="$(
			ftp_list "bash-$rcVersion-patches" \
				| sed -rne '/^bash[0-9]+-([0-9]{3})$/s//\1/p' \
				| tail -1 \
				|| :
		)"
	fi
	patchlevel="${patchlevel#0}"
	patchlevel="${patchlevel#0}"
	: "${patchlevel:=0}"
	[[ "$patchlevel" =~ ^[0-9]+$ ]]

	patchbase=
	if [ "$version" = "$rcVersion" ] && [[ "$baseline" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]; then
		patchbase="${baseline#*.*.}"
	fi
	: "${patchbase:=0}"

	fullVersion="$baseline"
	if [[ "$fullVersion" =~ ^[0-9]+[.][0-9]+$ ]]; then
		fullVersion+='.0'
	fi
	if [ "$version" = "$rcVersion" ] && [[ "$fullVersion" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] && [ "$patchlevel" -gt "$patchbase" ]; then
		fullVersion="${fullVersion%.*}.$patchlevel"
	fi

	echo "$version: $fullVersion"

	export fullVersion baseline patchbase patchlevel
	json="$(jq <<<"$json" -c '
		(env.patchbase | tonumber) as $patchbase
		| (env.patchlevel | tonumber) as $patchlevel
		| .[env.version] = { version: env.fullVersion }
		+ if env.baseline != env.fullVersion or $patchbase > 0 then
			{
				baseline: (
					if env.baseline != env.fullVersion then { version: env.baseline } else {} end
					+ if $patchbase > 0 then { patch: env.patchbase } else {} end
				),
			}
		else {} end
		+ if $patchlevel > 0 then
			{
				patch: { version: env.patchlevel },
			}
		else {} end
	')"
done

jq <<<"$json" -S . > versions.json
