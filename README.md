# squid-proxy
A lightweight, non-root Squid proxy container based on Alpine Linux, designed to run in AWS ECS. ACLs are fully configurable via ECS task definition environment variables — no image rebuild required.

## Features

- **Alpine 3.19** base image (minimal attack surface)
- Runs as **non-root user** `proxyuser` (uid/gid `10001`)
- No on-disk cache — pure forwarding proxy
- Privacy hardening: strips `X-Forwarded-For`, `Via` headers
- Logs to `stdout`/`stderr` (CloudWatch-friendly)
- ACLs injected at container startup from environment variables

## Project Structure

```
squid-proxy/
├── Dockerfile            # Image definition
├── squid.conf.template   # Base Squid config with ACL placeholders
├── entrypoint.sh         # Builds squid.conf from env vars and starts Squid
└── README.md
```

## Environment Variables

All variables are **optional**. Omitting a variable simply disables that ACL.

| Variable | Format | Description |
|---|---|---|
| `ALLOWED_IPS` | Comma-separated CIDRs/IPs | Source IPs/ranges permitted to use the proxy |
| `ALLOWED_DOMAINS` | Comma-separated domain suffixes | Destination domains to allow (prefix with `.` to match subdomains) |
| `ALLOWED_URL_REGEX` | Space-separated regex patterns | URL regex allow-list applied after domain rules |
| `DENIED_DOMAINS` | Comma-separated domain suffixes | Destination domains to explicitly block (evaluated before allow rules) |

### Examples

```
ALLOWED_IPS=10.0.0.0/8,172.16.0.0/12
ALLOWED_DOMAINS=.amazonaws.com,.example.com,internal.corp
ALLOWED_URL_REGEX=^https://api\.example\.com/ ^https://s3\.amazonaws\.com/my-bucket/
DENIED_DOMAINS=.malware.io,.badsite.com
```

## Build & Push to Amazon ECR

```bash
# Authenticate with ECR
aws ecr get-login-password --region <region> | \
  docker login --username AWS --password-stdin <account_id>.dkr.ecr.<region>.amazonaws.com

# Build
docker build -t squid-proxy:latest .

# Tag
docker tag squid-proxy:latest <account_id>.dkr.ecr.<region>.amazonaws.com/squid-proxy:latest

# Push
docker push <account_id>.dkr.ecr.<region>.amazonaws.com/squid-proxy:latest
```

## ECS Task Definition

### Container definition snippet

```json
{
  "name": "squid-proxy",
  "image": "<account_id>.dkr.ecr.<region>.amazonaws.com/squid-proxy:latest",
  "portMappings": [
    {
      "containerPort": 3128,
      "protocol": "tcp"
    }
  ],
  "environment": [
    { "name": "ALLOWED_IPS",       "value": "10.0.0.0/8,172.16.0.0/12" },
    { "name": "ALLOWED_DOMAINS",   "value": ".amazonaws.com,.example.com" },
    { "name": "ALLOWED_URL_REGEX", "value": "^https://api\\.example\\.com/" },
    { "name": "DENIED_DOMAINS",    "value": ".malware.io,.badsite.com" }
  ],
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/squid-proxy",
      "awslogs-region": "<region>",
      "awslogs-stream-prefix": "squid"
    }
  },
  "user": "10001"
}
```

> **Tip:** Store sensitive ACL values in AWS Secrets Manager or SSM Parameter Store and reference them via `secrets` instead of `environment` in the task definition.

## Local Testing

Run locally to verify ACL behaviour before pushing to ECR:

```bash
docker build -t squid-proxy:latest .

docker run --rm -p 3128:3128 \
  -e ALLOWED_IPS="0.0.0.0/0" \
  -e ALLOWED_DOMAINS=".example.com,.amazonaws.com" \
  -e DENIED_DOMAINS=".badsite.com" \
  squid-proxy:latest
```

Test through the proxy:

```bash
# Should succeed
curl -x http://localhost:3128 https://www.example.com

# Should be blocked (denied domain)
curl -x http://localhost:3128 https://www.badsite.com
```

## Access Control Logic

Rules are evaluated in this order:

1. `localhost` (`127.0.0.1`) — always allowed (for health checks)
2. **DENIED_DOMAINS** — blocked immediately if matched
3. **ALLOWED_IPS** — allowed if source IP matches
4. **ALLOWED_DOMAINS** — allowed if destination domain matches
5. **ALLOWED_URL_REGEX** — allowed if URL matches a regex pattern
6. Everything else — **denied**

## Security Notes

- `forwarded_for delete` and `via off` prevent the proxy from leaking client IP addresses to upstream servers.
- No disk cache is configured; the container holds no persistent data.
- The container runs entirely as uid `10001` — the root filesystem is never written to after build time
