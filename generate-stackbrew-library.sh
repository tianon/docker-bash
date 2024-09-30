#!/bin/bash
set -eu

declare -A aliases=(
	[5.3-rc]='rc'
	[5.2]='5 latest'
	[4.4]='4'
	[3.2]='3'
)

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

if [ "$#" -eq 0 ]; then
	versions="$(jq -r 'keys | map(@sh) | join(" ")' versions.json)"
	eval "set -- $versions"
fi

# sort version numbers with highest first
IFS=$'\n'; set -- $(sort -rV <<<"$*"); unset IFS

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		fileCommit \
			Dockerfile \
			$(git show HEAD:./Dockerfile | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			')
	)
}

getArches() {
	local repo="$1"; shift
	local officialImagesBase="${BASHBREW_LIBRARY:-https://github.com/docker-library/official-images/raw/HEAD/library}/"

	local parentRepoToArchesStr
	parentRepoToArchesStr="$(
		find -name 'Dockerfile' -exec awk -v officialImagesBase="$officialImagesBase" '
				toupper($1) == "FROM" && $2 !~ /^('"$repo"'|scratch|.*\/.*)(:|$)/ {
					printf "%s%s\n", officialImagesBase, $2
				}
			' '{}' + \
			| sort -u \
			| xargs -r bashbrew cat --format '["{{ .RepoName }}:{{ .TagName }}"]="{{ join " " .TagEntry.Architectures }}"'
	)"
	eval "declare -g -A parentRepoToArches=( $parentRepoToArchesStr )"
}
getArches 'bash'

cat <<-EOH
# this file is generated via https://github.com/tianon/docker-bash/blob/$(fileCommit "$self")/$self

Maintainers: Tianon Gravi <admwiggin@gmail.com> (@tianon)
GitRepo: https://github.com/tianon/docker-bash.git
EOH

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

for version; do
	export version

	fullVersion="$(jq -r '.[env.version].version' versions.json)"
	if [ "$version" = 'devel' ]; then
		fullVersion="$version-$fullVersion"
	fi

	versionAliases=(
		$fullVersion
		$version
		${aliases[$version]:-}
	)

	parent="$(awk 'toupper($1) == "FROM" { print $2 }' "$version/Dockerfile")"
	arches="${parentRepoToArches[$parent]}"

	alpine="${parent#*:}" # "3.14"
	suiteAliases=( "${versionAliases[@]/%/-alpine$alpine}" )
	suiteAliases=( "${suiteAliases[@]//latest-/}" )

	commit="$(dirCommit "$version")"

	echo
	cat <<-EOE
		Tags: $(join ', ' "${versionAliases[@]}" "${suiteAliases[@]}")
		Architectures: $(join ', ' $arches)
		GitCommit: $commit
		Directory: $version
	EOE
done
