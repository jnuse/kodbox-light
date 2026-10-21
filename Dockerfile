# syntax=docker/dockerfile:1

ARG PHP_VERSION=8.5

# ---------- 扩展编译 ----------
FROM php:${PHP_VERSION}-fpm-alpine AS builder

ARG EXT_SET=recommended
COPY extensions/${EXT_SET}.txt /tmp/extensions.txt

RUN apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    libpng-dev libjpeg-turbo-dev freetype-dev \
    libzip-dev sqlite-dev icu-dev

RUN set -eux; \
    if grep -qx gd /tmp/extensions.txt; then \
        docker-php-ext-configure gd --with-freetype --with-jpeg; \
    fi; \
    grep -v '^#' /tmp/extensions.txt | xargs docker-php-ext-install -j"$(nproc)"

# ---------- 运行 ----------
FROM php:${PHP_VERSION}-fpm-alpine AS runtime

RUN apk add --no-cache nginx tzdata \
    libpng libjpeg-turbo freetype \
    libzip sqlite-libs icu-libs icu-data-full

COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /tmp/extensions.txt /tmp/extensions.txt

RUN set -eux; \
    for ext in $(grep -v '^#' /tmp/extensions.txt); do \
        docker-php-ext-enable "$ext"; \
    done; \
    rm /tmp/extensions.txt; \
    php -m; \
    php -m | grep -qx mbstring

COPY php.ini /usr/local/etc/php/conf.d/php.ini
COPY opcache.ini /usr/local/etc/php/conf.d/opcache.ini
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN set -eux; \
    sed -i \
        -e 's|^listen = 9000|listen = /run/php-fpm.sock|' \
        -e 's|^;listen.owner = .*|listen.owner = www-data|' \
        -e 's|^;listen.group = .*|listen.group = www-data|' \
        -e 's|^;listen.mode = .*|listen.mode = 0660|' \
        -e 's|^;request_terminate_timeout = .*|request_terminate_timeout = 3600|' \
        -e 's|^pm.max_children = .*|pm.max_children = 3|' \
        -e 's|^pm.start_servers = .*|pm.start_servers = 1|' \
        -e 's|^pm.min_spare_servers = .*|pm.min_spare_servers = 1|' \
        -e 's|^pm.max_spare_servers = .*|pm.max_spare_servers = 2|' \
        -e 's|^;pm.max_requests = .*|pm.max_requests = 500|' \
        /usr/local/etc/php-fpm.d/www.conf; \
    mkdir -p /run /var/www/html; \
    chown -R www-data:www-data /run

WORKDIR /var/www/html
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]