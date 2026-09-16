# The stock php:8.3-apache ships no gd, but bhl-all-the-pages' tile.php needs it
# (imagecreatefromwebp / imagecreatetruecolor / imagewebp) to build the z>=10
# detail tiles on demand — without it those tiles are a PHP fatal.
#
# Building the extensions in here rather than in docker-compose's `command:`
# means they are compiled once at image build, not on every container start.
# pdo_sqlite and sqlite3 are already compiled into the official PHP image, so
# they are deliberately not listed below — asking for pdo_sqlite here fails the
# build unless libsqlite3-dev is also installed.
# ADD EXTENSIONS FOR NEW DEMOS HERE (intl, zip, pdo_mysql, pdo_pgsql, ...),
# remembering that most need their -dev library in the apt line above.
FROM php:8.3-apache

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libwebp-dev libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
 && docker-php-ext-configure gd --with-webp --with-jpeg --with-freetype \
 && docker-php-ext-install -j"$(nproc)" gd \
 && a2enmod rewrite \
 && rm -rf /var/lib/apt/lists/*
