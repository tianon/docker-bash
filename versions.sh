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

ftpBase='https://ftp.gnu.org/gnu/bash'

allBaseVersions="$(
	wget -qO- "$ftpBase/" \
		| sed -rne '/^(.*[/"[:space:]])?bash-([0-9].+)[.]tar[.]gz([/"[:space:]].*)?$/s//\2/p' \
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
		yq='./.yq'
		# https://github.com/mikefarah/yq/releases
		# TODO detect host architecture
		yqUrl='https://github.com/mikefarah/yq/releases/download/v4.44.5/yq_linux_amd64'
		yqSha256='638c4b251c49201fc94b598834b715f8f1c6e9b1854d2820772d2c79f0289002'
		if command -v yq &> /dev/null; then
			# TODO verify that the "yq" in PATH is https://github.com/mikefarah/yq, not the python-based version you'd get from "apt-get install yq" somehow?  maybe they're compatible enough for our needs that it doesn't matter?
			yq='yq'
		elif [ ! -x "$yq" ] || ! sha256sum <<<"$yqSha256 *$yq" --quiet --strict --check; then
			wget -qO "$yq.new" "$yqUrl"
			sha256sum <<<"$yqSha256 *$yq.new" --quiet --strict --check
			chmod +x "$yq.new"
			"$yq.new" --version
			mv "$yq.new" "$yq"
		fi

		# https://github.com/docker-library/faq#can-i-use-a-bot-to-make-my-image-update-prs
		snapshotDate="$(date --utc --date 'last monday 23:59:59' '+%s')"
		commit='devel' # this is also our iteration variable, so if we don't find a suitable commit each time through this loop, we'll use the last commit of the previous list to get a list of new (older) commits until we find one suitably old enough
		fullVersion=
		while [ -z "$fullVersion" ]; do
			commits="$(
				wget -qO- "https://git.savannah.gnu.org/cgit/bash.git/atom/?h=$commit" \
					| "$yq" --input-format xml --output-format json \
					| jq -r '
						.feed.entry[]
						| select(
							(.id | startswith("urn:sha1:"))
							and .updated // .published
							and .title
						)
						| [
							@sh "commit=\(.id | ltrimstr("urn:sha1:"))",
							@sh "date=\([ .updated, .published ] | sort | reverse[0])",
							@sh "desc=\(.title)",
							empty
						]
						| join("\n")
						| @sh
					'
			)"
			eval "commits=( $commits )"
			if [ "${#commits[@]}" -eq 0 ]; then
				echo >&2 "error: got no commits when listing history from $commit"
				exit 1
			fi
			for commitShell in "${commits[@]}"; do
				unset commit date desc
				eval "$commitShell"
				[ -n "$commit" ]
				[ -n "$date" ]
				[ -n "$desc" ]
				date="$(date --utc --date "$date" '+%s')"
				if [ "$date" -le "$snapshotDate" ]; then
					fullVersion="$commit"
					break 2
				fi
			done
		done
		if [ -z "$fullVersion" ]; then
			snapshotDateStr="$(date --utc --date "@$snapshotDate" '+%Y-%m-%d %H:%M:%S %Z')"
			echo >&2 "error: cannot find full version for $version (maybe too many commits since $snapshotDateStr? cgit changed the atom feed format? yq changed how it parses XML?)"
			exit 1
		fi
		[ "$commit" = "$fullVersion" ]
		[ -n "$date" ]
		[ -n "$desc" ]

		if timestamp="$(sed -rne '/.*[[:space:]]+bash-([0-9]+)[[:space:]]+.*/s//\1/p' <<<"$desc")" && [ -n "$timestamp" ]; then
			: # "commit bash-20210305 snapshot" (https://git.savannah.gnu.org/cgit/bash.git/commit/?h=devel&id=11bf534f3628cc0a592866ee4f689beca473f548)
		else
			timestamp="$(date --utc --date "@$date" '+%Y%m%d')"
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
			{ wget -qO- "$ftpBase/bash-$rcVersion-patches/" || :; } \
				| sed -rne '/^(.*[/"[:space:]])?bash[0-9]+-([0-9]{3})([/"[:space:]].*)?$/s//\2/p' \
				| tail -1
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
