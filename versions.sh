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

alpine="$(
	bashbrew cat --format '{{ .TagEntry.Tags | join "\n" }}' https://github.com/docker-library/official-images/raw/HEAD/library/alpine:latest \
		| grep -E '^[0-9]+[.][0-9]+$'
)"
[ "$(wc -l <<<"$alpine")" = 1 ]
export alpine

tmp="$(mktemp -d)"
trap "$(printf 'rm -rf %q' "$tmp")" EXIT

for version in "${versions[@]}"; do
	export version

	rcVersion="${version%-rc}"
	rcGrepV='-v'
	if [ "$version" != "$rcVersion" ]; then
		rcGrepV=
	fi

	if [ "$version" = 'devel' ]; then
		git clone --quiet --branch devel --depth 10 https://git.savannah.gnu.org/git/bash.git "$tmp/devel"
		snapshotDate="$(TZ=UTC date --date 'last monday 23:59:59' '+%Y-%m-%d %H:%M:%S %Z')" # https://github.com/docker-library/faq#can-i-use-a-bot-to-make-my-image-update-prs
		commit="$(git -C "$tmp/devel" log --before="$snapshotDate" --format='format:%H' --max-count=1)"
		if [ -z "$commit" ]; then
			echo >&2 "error: cannot determine commit for $version (from https://git.savannah.gnu.org/cgit/bash.git)"
			exit 1
		fi
		desc="$(git -C "$tmp/devel" log --max-count=1 --format='format:%s' "$commit")"
		[ -n "$desc" ]
		if timestamp="$(sed -rne '/.*[[:space:]]+bash-([0-9]+)[[:space:]]+.*/s//\1/p' <<<"$desc")" && [ -n "$timestamp" ]; then
			: # "commit bash-20210305 snapshot"
		else
			timestamp="$(git -C "$tmp/devel" log --max-count=1 --format='format:%aI' "$commit")" # ideally we'd use "%as" and just axe "-" but that requires newer Git than Debian 10 has /o\
			timestamp="${timestamp%%T*}"
			timestamp="${timestamp//-/}"
		fi

		echo "$version: $commit ($timestamp -- $desc)"

		export commit timestamp desc
		json="$(jq <<<"$json" -c '.[env.version] = {
			version: env.timestamp,
			commit: { version: env.commit, description: env.desc },
			alpine: { version: env.alpine },
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
		| .[env.version] = { version: env.fullVersion, alpine: { version: env.alpine } }
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
