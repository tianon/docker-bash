#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM alpine:3.22

# https://git.savannah.gnu.org/cgit/bash.git/log/?h=devel
# https://github.com/tianon/mirror-bash/commits/devel
ENV _BASH_COMMIT 4e705ed53ac364ee110f0b2fbeeab9d3301fcb6b
# fix expansion of $* and $@ in contexts where word splitting is not performed to be more consistent across different word expansions; fix pathname canonicalization when setting $BASH
ENV _BASH_VERSION devel-20251124
# prefixed with "_" since "$BASH..." have meaning in Bash parlance

COPY alpine-strcpy.patch /usr/local/src/tianon-bash-patches/

RUN set -eux; \
	\
	apk add --no-cache --virtual .build-deps \
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
	wget -T2 -O bash.tar.gz "https://git.savannah.gnu.org/cgit/bash.git/snapshot/bash-$_BASH_COMMIT.tar.gz" || \
		wget -O bash.tar.gz "https://github.com/tianon/mirror-bash/archive/$_BASH_COMMIT.tar.gz"; \
	\
	mkdir -p /usr/local/src/bash; \
	tar \
		--extract \
		--file=bash.tar.gz \
		--strip-components=1 \
		--directory=/usr/local/src/bash \
	; \
	rm bash.tar.gz; \
	\
	if [ -d bash-patches ]; then \
		apk add --no-cache --virtual .patch-deps patch; \
		for p in bash-patches/*; do \
			patch \
				--directory=/usr/local/src/bash \
				--input="$(readlink -f "$p")" \
				--strip=0 \
			; \
			rm "$p"; \
		done; \
		rmdir bash-patches; \
		apk del --no-network .patch-deps; \
	fi; \
	\
	for p in /usr/local/src/tianon-bash-patches/*; do \
		patch \
			--directory=/usr/local/src/bash \
			--input="$p" \
			--strip=1 \
		; \
	done; \
	\
	cd /usr/local/src/bash; \
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
	rm -r /usr/local/src/bash; \
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
	apk add --no-network --virtual .bash-rundeps $runDeps; \
	apk del --no-network .build-deps; \
	\
	[ "$(which bash)" = '/usr/local/bin/bash' ]; \
	bash --version; \
	bash -c 'help' > /dev/null

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["bash"]
