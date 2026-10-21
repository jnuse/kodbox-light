#!/bin/sh
set -e

if [ ! -f /var/www/html/index.php ]; then
    echo "ERROR: /var/www/html/index.php not found." >&2
    echo "Kodbox source must be mounted at /var/www/html." >&2
    echo "On the host, ensure ownership matches container www-data (UID 82):" >&2
    echo "  chown -R 82:82 /path/to/kodbox" >&2
    exit 1
fi

mkdir -p /run
chown www-data:www-data /run 2>/dev/null || true

nginx

exec php-fpm -F