#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

ftpBase='ftp://ftp.gnu.org/gnu/bash'
allBaseVersions="$(
	curl --silent --list-only "$ftpBase/" \
		| grep -E '^bash-[0-9].*\.tar\.gz$' \
		| sed -r 's/^bash-|\.tar\.gz$//g'
)"

travisEnv=
for version in "${versions[@]}"; do
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
				| sed -n '/^Subject: /{s///p;q}' \
				|| :
		)"
		[ -n "$desc" ]
		echo "$version: $commit ($desc)"
		sed -ri -e 's/^(ENV _BASH_COMMIT) .*/\1 '"$commit"'/' \
			-e 's!^(ENV _BASH_COMMIT_DESC) .*!\1 '"$desc"'!' \
			"$version/Dockerfile"
		cp -a docker-entrypoint.sh "$version/"
		travisEnv='\n  - VERSION='"$version$travisEnv"
		continue
	fi

	bashVersion="$rcVersion"

	IFS=$'\n'
	allVersions=( $(
		echo "$allBaseVersions" \
			| grep -E "^$bashVersion([.-]|\$)" \
			| grep -E $rcGrepV -- '-(rc|beta|alpha)' \
			| sort -rV
	) )
	allPatches=( $(
		curl --silent --list-only "$ftpBase/bash-$bashVersion-patches/" \
			| grep -E '^bash'"${bashVersion//./}"'-[0-9]{3}$' \
			| sed -r 's/^bash'"${bashVersion//./}"'-0*//g' \
			| sort -rn \
		|| true
	) )
	unset IFS

	if [ "${#allVersions[@]}" -eq 0 ]; then
		echo >&2 "error: cannot find any releases of $version in $ftpBase"
		exit 1
	fi
	latestVersion="${allVersions[0]}"

	latestPatch='0'
	if [ "${#allPatches[@]}" -gt 0 ]; then
		latestPatch="${allPatches[0]}"
	fi

	patchLevel='0'
	if [[ "$latestVersion" == *.*.* ]]; then
		patchLevel="${latestVersion##*.*.}"
	fi

	if [ "$rcVersion" != "$version" ]; then
		bashVersion="$latestVersion" # "5.0-beta", "5.0-alpha", etc
	fi

	echo "$version: $latestVersion"

	sed -ri \
		-e 's/^(ENV _BASH_VERSION) .*/\1 '"$bashVersion"'/' \
		-e 's/^(ENV _BASH_PATCH_LEVEL) .*/\1 '"$patchLevel"'/' \
		-e 's/^(ENV _BASH_LATEST_PATCH) .*/\1 '"$latestPatch"'/' \
		"$version/Dockerfile"
	cp -a docker-entrypoint.sh "$version/"

	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
