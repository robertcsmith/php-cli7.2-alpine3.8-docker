FROM robertcsmith/base1.1-alpine3.8-docker

LABEL  robertcsmith.php-cli.namespace="robertcsmith/" \
    robertcsmith.php-cli.name="php-cli" \
    robertcsmith.php-cli.release="7.2" \
    robertcsmith.php-cli.flavor="-alpine3.8" \
    robertcsmith.php-cli.version="-docker" \
    robertcsmith.php-cli.tag=":1.0" \
    robertcsmith.php-cli.image="robertcsmith/php-cli7.2-alpine3.8-docker" \
    robertcsmith.php-cli.vcs-url="https://github.com/robertcsmith/php-cli7.2-alpine3.8-docker" \
    robertcsmith.php-cli.maintainer="Robert C Smith <robertchristophersmith@gmail.com>" \
    robertcsmith.php-cli.usage="./README.md" \
    robertcsmith.php-cli.description="\
        This base php-cli image can, through bind mounts and environmental variables, provide a full \
        PHP interpreter image when given source code and a simple .conf file. Couple this with a database, \
        a cache perhaps and a web server and you should have a solid stack with all the benefits Docker \
        has to offer."

ENV	PHP_VERSION="7.2.11" \
    PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2"
ENV PHP_URL="http://us2.php.net/get/php-${PHP_VERSION}.tar.gz/from/this/mirror" \
    PHP_ASC_URL="http://us2.php.net/get/php-${PHP_VERSION}.tar.gz.asc/from/this/mirror" \
    PHP_CPPFLAGS="${PHP_CFLAGS}" \
    PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie" \
    PHP_INI_DIR="/usr/local/etc/php/" \
    PHP_CLI_INI_VERSION="-development" \
    PHP_SHA256="180c63a9647c0a50d438b6bd5c7a8e7a11bceee8ad613a59d3ef15151fc158d4" \
    GPG_KEYS="1729F83938DA44E27BA0F4D3DBDB397470D12172 B1B44D8F021E4E2D6021E995DC9FF8D3EE5AF27F" \
    PHP_EXTRA_CONFIGURE_ARGS="" \
    PHPIZE_DEPS="autoconf dpkg-dev dpkg file g++ gcc libc-dev make pkgconf re2c"

# For comunication over sockets we need to create consistant group IDs.
# 82 is the standard uid/gid for "www-data" in Alpine's PHP and
# 101 seems to be the standard uid/gid for "nginx" in Alpine's nginx flavor.
RUN set -x; \
    addgroup -S -g 82 www-data && addgroup -S -g 101 nginx; \
    addgroup app www-data && addgroup app nginx;

COPY docker-php-source docker-php-ext-* docker-php-entrypoint /usr/local/bin/

# persistent deps
# https://github.com/docker-library/php/issues/494
# modified image to decompress gz over xz tarballs and their sources
RUN set -ex;
    apk update && apk upgrade; \
    apk add --no-cache --virtual .persistent-deps ca-certificates curl libressl;
    \
    mkdir -p /usr/src $PHP_INI_DIR/conf.d && cd /usr/src; \
    # Download the tarball
    wget -O php.tar.gz "${PHP_URL}"; \
    # Validate the sha256sum of the tarball against what we know it should be
    if [ -n "$PHP_SHA256" ]; then \
        echo "$PHP_SHA256 *php.tar.gz" | sha256sum -c -; \
    fi; \
    # NOTE: removed MD5 checking as we have no value to compare
    # Finally we verify against the .asc file as proof this is a legit tarball, get the keys
    # as yet another method of validation leaving the file ready for extraction with peace of mind
    if [ -n $PHP_ASC_URL ]; then \
        wget -O php.tar.gz.asc $PHP_ASC_URL; \
        GNUPGHOME="$(mktemp -d)"; \
        for key in $GPG_KEYS; do \
            gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
        done; \
        gpg --batch --verify php.tar.gz.asc php.tar.gz; \
        command -v gpgconf > /dev/null && gpgconf --kill all; \
        rm -rf $GNUPGHOME; \
    fi; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        argon2-dev \
        bison \
        curl-dev \
        freetype-dev \
        gettext-dev \
        libgd \
        icu-dev \
        libedit-dev \
        libintl \
        libjpeg-turbo-dev \
        libmcrypt-dev \
        libpng-dev \
        libressl-dev \
        libsodium-dev \
        libwebp-dev \
        libxml2-dev \
        libxpm-dev \
        libxslt-dev \
        libzip-dev \
        php7-dom \
        php7-pcntl \
        php7-pdo \
        php7-pdo_mysql \
        php7-pdo_sqlite \
        sqlite-dev; \
    export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS";\
    docker-php-source extract;\
    gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)";\
    cd /usr/src/php; \
    ./configure \
        --build="${gnuArch}" \
        --localstatedir=/var \
        --with-config-file-path="${PHP_INI_DIR}" \
        --with-config-file-scan-dir="${PHP_INI_DIR}/conf.d" \
        # make sure invalid --configure-flags are fatal errors intead of just warnings
        --enable-option-checking=fatal \
        # https://github.com/docker-library/php/issues/439
        --with-mhash \
        # --enable-ftp is included here because ftp_ssl_connect() needs ftp to be compiled statically (see https://github.com/docker-library/php/issues/236)
        --enable-ftp \
        # --enable-mbstring is included here because otherwise there's no way to get pecl to use it properly (see https://github.com/docker-library/php/issues/195)
        --enable-mbstring=shared \
        # --enable-mysqlnd is included here because it's harder to compile after the fact than extensions are (since it's a plugin for several extensions, not an extension in itself)
        --enable-mysqlnd=/usr/local \
	        --with-mysqli=mysqlnd \
	            --with-mysql-sock=/run/mysqld/mysqld.sock \
        --enable-pdo=shared \
            --with-pdo-mysql=shared \
            --with-pdo-sqlite=shared \
            --with-sqlite3=shared \
        # https://wiki.php.net/rfc/argon2_password_hash (7.2+)
        --with-password-argon2 \
        # https://wiki.php.net/rfc/libsodium
        --with-sodium=shared \
        --enable-ctype=shared \
        --with-curl=shared \
        --enable-dom=shared \
        --with-gd=shared \
            --with-freetype-dir=/usr/local \
            --disable-gd-jis-conv \
            --with-jpeg-dir=/usr/local \
            --with-png-dir=/usr/local \
            --with-webp-dir=/usr/local \
        --with-gettext=shared \
        --with-iconv=shared \
        --enable-intl=shared \
        --enable-json=shared \
        --enable-libxml \
            --with-libxml-dir=/usr/local \
        --enable-opcache=shared \
        --with-openssl=shared  \
            --with-system-ciphers \
        --enable-phar=shared \
        --without-readline \
        --enable-session=shared \
        --enable-simplexml=shared \
        --enable-soap=shared \
        --enable-sockets=shared \
        --enable-xml=shared \
        --enable-xmlreader=shared \
        --enable-xmlwriter=shared \
            --with-xsl=shared \
        --enable-zip=shared \
            --with-libzip=/usr/local \
            --with-zlib \
                --with-zlib-dir=/usr/local \
        $PHP_EXTRA_CONFIGURE_ARGS; \
    make -j "$(nproc)" && make install; \
    { find /usr/local/bin /usr/local/sbin -type f -perm +0111 -exec strip --strip-all '{}' + || true; } && make clean; \
    cd /; \
    run-deps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-cache --virtual .php-rundeps $run-deps; \
    pear channel-update pear.php.net && pecl channel-update pecl.php.net; \
    # sodium was built as a shared module (so that it can be replaced later if so desired), so
    # let's enable it too (https://github.com/docker-library/php/issues/598)
    docker-php-ext-enable sodium; \
    # cleanup
    apk del .build-deps && docker-php-source delete && rm -rf /var/cache/apk/* 2>/dev/null;

COPY --chown=app:root files/php.ini-${PHP_CLI_INI_VERSION} ${PHP_INI_DIR}/php.ini

# Final directory mods
RUN	set -ex; \
    mkdir -p /var/run/php /var/www /var/log 2>/dev/null; \
    touch /var/run/php/php-cli.pid /var/log/php-errors.log; \
    chown -R app:root /var/run/php/ && chmod -R 0660 /var/run/php/; \
    chown app /var/log/php-errors.log && chmod -R 0664 /var/log/php-errors.log;

#   This is an intermediate image and we only want to remove our base packages in a final image
#	source base-pkg-mgr --uninstall;

ENTRYPOINT ["docker-php-entrypoint"]

CMD ["php", "-a"]
