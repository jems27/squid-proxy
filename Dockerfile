FROM alpine:3.19

# Install squid and bash (needed for entrypoint logic)
RUN apk add --no-cache squid bash

# Create dedicated non-root group and user with uid/gid 10001
RUN addgroup -g 10001 -S proxyuser \
    && adduser -u 10001 -S -G proxyuser -H -D proxyuser

# Create all required runtime directories owned by proxyuser
RUN mkdir -p \
        /etc/squid \
        /var/cache/squid \
        /var/log/squid \
        /run/squid \
    && chown -R proxyuser:proxyuser \
        /etc/squid \
        /var/cache/squid \
        /var/log/squid \
        /run/squid \
    && chmod 750 \
        /var/cache/squid \
        /var/log/squid \
        /run/squid

# Copy config template and entrypoint
COPY --chown=proxyuser:proxyuser squid.conf.template /etc/squid/squid.conf.template
COPY --chown=proxyuser:proxyuser entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

# Drop to non-root user (uid 10001)
USER 10001

# Squid default proxy port
EXPOSE 3128

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
