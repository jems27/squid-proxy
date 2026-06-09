#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh  –  Build squid.conf from environment variables then exec squid
#
# Supported environment variables (all optional):
#
#   ALLOWED_IPS        Comma-separated CIDR/IP list allowed to use this proxy
#                      e.g. "10.0.0.0/8,172.16.0.0/12,192.168.1.100"
#
#   ALLOWED_DOMAINS    Comma-separated domain suffixes to allow
#                      e.g. ".example.com,.amazonaws.com,s3.us-east-1.amazonaws.com"
#
#   ALLOWED_URL_REGEX  Space-separated URL regex patterns to allow
#                      e.g. "^https://api\.example\.com/ ^http://internal\.corp/"
#
#   DENIED_DOMAINS     Comma-separated domain suffixes to explicitly block
#                      e.g. ".badsite.com,.malware.io"
# =============================================================================
set -euo pipefail

SQUID_CONF="/etc/squid/squid.conf"
TEMPLATE="/etc/squid/squid.conf.template"

# ---------------------------------------------------------------------------
# Helper: split a comma-separated string into an array
# ---------------------------------------------------------------------------
split_csv() {
  local input="$1"
  IFS=',' read -ra arr <<< "$input"
  printf '%s\n' "${arr[@]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
}

# ---------------------------------------------------------------------------
# Start with a fresh copy of the template
# ---------------------------------------------------------------------------
cp "$TEMPLATE" "$SQUID_CONF"

# ---------------------------------------------------------------------------
# 1. ALLOWED_IPS  →  acl allowed_ips src ...  +  http_access allow allowed_ips
# ---------------------------------------------------------------------------
if [[ -n "${ALLOWED_IPS:-}" ]]; then
  ip_acl_lines=""
  while IFS= read -r ip; do
    ip_acl_lines+="acl allowed_ips src ${ip}\n"
  done < <(split_csv "$ALLOWED_IPS")

  # Replace placeholder with acl lines
  sed -i "s|#ALLOWED_IPS_ACL#|${ip_acl_lines}|" "$SQUID_CONF"
  sed -i "s|#ALLOWED_IPS_ALLOW#|http_access allow allowed_ips|" "$SQUID_CONF"
else
  sed -i "/#ALLOWED_IPS_ACL#/d" "$SQUID_CONF"
  sed -i "/#ALLOWED_IPS_ALLOW#/d" "$SQUID_CONF"
fi

# ---------------------------------------------------------------------------
# 2. ALLOWED_DOMAINS  →  acl allowed_domains dstdomain ...  +  http_access allow
# ---------------------------------------------------------------------------
if [[ -n "${ALLOWED_DOMAINS:-}" ]]; then
  domain_acl_lines=""
  while IFS= read -r domain; do
    domain_acl_lines+="acl allowed_domains dstdomain ${domain}\n"
  done < <(split_csv "$ALLOWED_DOMAINS")

  sed -i "s|#ALLOWED_DOMAINS_ACL#|${domain_acl_lines}|" "$SQUID_CONF"
  sed -i "s|#ALLOWED_DOMAINS_ALLOW#|http_access allow allowed_domains|" "$SQUID_CONF"
else
  sed -i "/#ALLOWED_DOMAINS_ACL#/d" "$SQUID_CONF"
  sed -i "/#ALLOWED_DOMAINS_ALLOW#/d" "$SQUID_CONF"
fi

# ---------------------------------------------------------------------------
# 3. ALLOWED_URL_REGEX  →  acl allowed_url_regex url_regex ...  +  http_access allow
# ---------------------------------------------------------------------------
if [[ -n "${ALLOWED_URL_REGEX:-}" ]]; then
  regex_acl_lines=""
  # Split on spaces (allow the user to quote individual patterns if needed)
  for pattern in $ALLOWED_URL_REGEX; do
    regex_acl_lines+="acl allowed_url_regex url_regex ${pattern}\n"
  done

  sed -i "s|#ALLOWED_URL_REGEX_ACL#|${regex_acl_lines}|" "$SQUID_CONF"
  sed -i "s|#ALLOWED_URL_REGEX_ALLOW#|http_access allow allowed_url_regex|" "$SQUID_CONF"
else
  sed -i "/#ALLOWED_URL_REGEX_ACL#/d" "$SQUID_CONF"
  sed -i "/#ALLOWED_URL_REGEX_ALLOW#/d" "$SQUID_CONF"
fi

# ---------------------------------------------------------------------------
# 4. DENIED_DOMAINS  →  acl denied_domains dstdomain ...  +  http_access deny
# ---------------------------------------------------------------------------
if [[ -n "${DENIED_DOMAINS:-}" ]]; then
  deny_acl_lines=""
  while IFS= read -r domain; do
    deny_acl_lines+="acl denied_domains dstdomain ${domain}\n"
  done < <(split_csv "$DENIED_DOMAINS")

  sed -i "s|#DENIED_DOMAINS_ACL#|${deny_acl_lines}|" "$SQUID_CONF"
  sed -i "s|#DENIED_DOMAINS_DENY#|http_access deny denied_domains|" "$SQUID_CONF"
else
  sed -i "/#DENIED_DOMAINS_ACL#/d" "$SQUID_CONF"
  sed -i "/#DENIED_DOMAINS_DENY#/d" "$SQUID_CONF"
fi

# ---------------------------------------------------------------------------
# Initialise the cache directory (safe to re-run)
# ---------------------------------------------------------------------------
echo "[entrypoint] Initialising squid cache directories..."
squid -z --foreground -f "$SQUID_CONF" 2>&1 || true

# ---------------------------------------------------------------------------
# Start squid in the foreground (required for ECS/container signal handling)
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting squid..."
exec squid --foreground -f "$SQUID_CONF"
