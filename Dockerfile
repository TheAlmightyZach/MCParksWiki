FROM mediawiki:1.46.2-fpm

# System packages
# (LuaSandbox for Scribunto already ships with the official mediawiki image)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        cron \
        nginx \
        supervisor \
        unzip \
    && rm -rf /var/lib/apt/lists/* \
    && chown -Rf www-data:www-data /var/lib/nginx

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Extensions — kept before the config copy so config edits don't re-clone everything
COPY config/var/www/html/composer.local.json /var/www/html/
COPY scripts/extensionInstaller.sh /tmp/extensionInstaller.sh
RUN bash /tmp/extensionInstaller.sh && rm /tmp/extensionInstaller.sh

# Config files and runtime scripts
COPY config /
COPY scripts /scripts
RUN rm -f /scripts/extensionInstaller.sh && \
    chmod +x /scripts/*.sh && \
    chown -R www-data:www-data /scripts && \
    chmod 644 /etc/cron.d/cron

EXPOSE 80
CMD ["/scripts/entrypoint.sh"]
