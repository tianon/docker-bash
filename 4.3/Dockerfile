#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM alpine:3.20

# https://ftp.gnu.org/gnu/bash/?C=M;O=D
ENV _BASH_VERSION 4.3.48
ENV _BASH_BASELINE 4.3.30
ENV _BASH_BASELINE_PATCH 30
# https://ftp.gnu.org/gnu/bash/bash-4.3-patches/?C=M;O=D
ENV _BASH_LATEST_PATCH 48
# prefixed with "_" since "$BASH..." have meaning in Bash parlance

# The global SOURCE_DATE_EPOCH is consumed by commands that are not associated with a source artifact.
# This is not propagated from --build-arg: https://github.com/moby/buildkit/issues/4576#issuecomment-2159501282
ENV SOURCE_DATE_EPOCH 0

RUN set -eux; \
	\
	apk add --no-cache --virtual .build-deps=0 \
		bison \
		coreutils \
		dpkg-dev dpkg \
		gcc \
		libc-dev \
		make \
		ncurses-dev \
		patch \
		tar \
	; \
	\
	wget -O bash.tar.gz "https://ftp.gnu.org/gnu/bash/bash-$_BASH_BASELINE.tar.gz"; \
	wget -O bash.tar.gz.sig "https://ftp.gnu.org/gnu/bash/bash-$_BASH_BASELINE.tar.gz.sig"; \
	\
	: "${_BASH_BASELINE_PATCH:=0}" "${_BASH_LATEST_PATCH:=0}"; \
	if [ "$_BASH_LATEST_PATCH" -gt "$_BASH_BASELINE_PATCH" ]; then \
		mkdir -p bash-patches; \
		first="$(printf '%03d' "$(( _BASH_BASELINE_PATCH + 1 ))")"; \
		last="$(printf '%03d' "$_BASH_LATEST_PATCH")"; \
		majorMinor="${_BASH_VERSION%.*}"; \
		for patch in $(seq -w "$first" "$last"); do \
			url="https://ftp.gnu.org/gnu/bash/bash-$majorMinor-patches/bash${majorMinor//./}-$patch"; \
			wget -O "bash-patches/$patch" "$url"; \
			wget -O "bash-patches/$patch.sig" "$url.sig"; \
		done; \
	fi; \
	\
	apk add --no-cache --virtual .gpg-deps=0 gnupg; \
	export GNUPGHOME="$(mktemp -d)"; \
# gpg: key 64EA74AB: public key "Chet Ramey <chet@cwru.edu>" imported
	gpg --batch --keyserver keyserver.ubuntu.com --recv-keys 7C0135FB088AAF6C66C650B9BB5869F064EA74AB; \
	gpg --batch --verify bash.tar.gz.sig bash.tar.gz; \
	rm bash.tar.gz.sig; \
	if [ -d bash-patches ]; then \
		for sig in bash-patches/*.sig; do \
			p="${sig%.sig}"; \
			gpg --batch --verify "$sig" "$p"; \
			rm "$sig"; \
		done; \
	fi; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME"; \
	apk del --no-network .gpg-deps; \
	\
	mkdir -p /usr/src/bash; \
	tar \
		--extract \
		--file=bash.tar.gz \
		--strip-components=1 \
		--directory=/usr/src/bash \
	; \
	rm bash.tar.gz; \
	\
	if [ -d bash-patches ]; then \
		apk add --no-cache --virtual .patch-deps=0 patch; \
		for p in bash-patches/*; do \
# --force is set for reproducing timestamps
			patch \
				--directory=/usr/src/bash \
				--input="$(readlink -f "$p")" \
				--strip=0 \
				--set-utc \
				--force \
			; \
			rm "$p"; \
		done; \
		rmdir bash-patches; \
		apk del --no-network .patch-deps; \
	fi; \
	SOURCE_DATE_EPOCH="$(find /usr/src/bash -type f -exec stat -c '%Y' {} + | sort -nr | head -n1)"; \
	export SOURCE_DATE_EPOCH; \
# for logging validation/edification
	date --date "@$SOURCE_DATE_EPOCH" --rfc-2822; \
	\
	cd /usr/src/bash; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
# update "config.guess" and "config.sub" to get more aggressively inclusive architecture support
	for f in config.guess config.sub; do \
		wget -O "support/$f" "https://git.savannah.gnu.org/cgit/config.git/plain/$f?id=7d3d27baf8107b630586c962c057e22149653deb"; \
	done; \
	./configure \
		--build="$gnuArch" \
		--enable-readline \
		--with-curses \
# musl does not implement brk/sbrk (they simply return -ENOMEM)
#   bash: xmalloc: locale.c:81: cannot allocate 18 bytes (0 bytes allocated)
		--without-bash-malloc \
	|| { \
		cat >&2 config.log; \
		false; \
	}; \
	make -j "$(nproc)"; \
	make install; \
	cd /; \
	rm -r /usr/src/bash; \
	\
# delete a few installed bits for smaller image size
	rm -rf \
		/usr/local/share/doc/bash/*.html \
		/usr/local/share/info \
		/usr/local/share/locale \
		/usr/local/share/man \
	; \
	\
	runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)"; \
	apk add --no-network --virtual .bash-rundeps=0 $runDeps; \
	apk del --no-network .build-deps; \
	\
	[ "$(which bash)" = '/usr/local/bin/bash' ]; \
	bash --version; \
	[ "$(bash -c 'echo "${BASH_VERSION%%[^0-9.]*}"')" = "$_BASH_VERSION" ]; \
	bash -c 'help' > /dev/null

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["bash"]
