#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM alpine:3.20

# https://git.savannah.gnu.org/cgit/bash.git/log/?h=devel
ENV _BASH_COMMIT 5edfaa45e791bbb2bf6c9342e13e5e364ff87bad
# third set of documentation updates: readline and history
ENV _BASH_VERSION devel-20241012
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
	wget -O bash.tar.gz "https://git.savannah.gnu.org/cgit/bash.git/snapshot/bash-$_BASH_COMMIT.tar.gz"; \
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
# https://lists.gnu.org/archive/html/bug-bash/2023-05/msg00011.html
	{ echo '#include <unistd.h>'; echo; cat /usr/src/bash/lib/sh/strscpy.c; } > /usr/src/bash/lib/sh/strscpy.c.new; \
	mv /usr/src/bash/lib/sh/strscpy.c.new /usr/src/bash/lib/sh/strscpy.c; \
	\
	cd /usr/src/bash; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
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
	bash -c 'help' > /dev/null

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["bash"]
