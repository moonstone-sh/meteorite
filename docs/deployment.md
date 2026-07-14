# Meteorite Deployment Guide

Meteorite binaries are self-contained Zig HTTP servers. This guide covers
common deployment patterns for production.

## Static Binary (Default)

The simplest deployment: a single binary with no runtime dependencies.

```bash
# Build a static release
meteorite build --mode release-static

# The binary is at dist/server
./dist/server
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `METEORITE_HOST` | `127.0.0.1` | Bind address |
| `METEORITE_PORT` | `8080` | Listen port |
| `METEORITE_UNIX_SOCKET_PATH` | (none) | UNIX socket path (overrides TCP) |
| `METEORITE_UNIX_SOCKET_MODE` | `0660` | Socket file permissions |

## Systemd (Linux)

### Service Unit

```ini
# /etc/systemd/system/meteorite.service
[Unit]
Description=Meteorite HTTP Server
After=network.target

[Service]
Type=simple
User=meteorite
Group=meteorite
WorkingDirectory=/opt/meteorite
ExecStart=/opt/meteorite/bin/server
Environment=METEORITE_HOST=0.0.0.0
Environment=METEORITE_PORT=8080
Restart=on-failure
RestartSec=5

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/opt/meteorite

# Resource limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

### UNIX Socket Variant

```ini
[Service]
ExecStart=/opt/meteorite/bin/server
Environment=METEORITE_UNIX_SOCKET_PATH=/run/meteorite/meteorite.sock
Environment=METEORITE_UNIX_SOCKET_MODE=0660
RuntimeDirectory=meteorite
```

### Managing the Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable meteorite
sudo systemctl start meteorite
sudo systemctl status meteorite
journalctl -u meteorite -f
```

## Launchd (macOS)

### plist File

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.meteorite.server</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/meteorite/bin/server</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>METEORITE_HOST</key>
    <string>127.0.0.1</string>
    <key>METEORITE_PORT</key>
    <string>8080</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>/var/log/meteorite/error.log</string>
  <key>StandardOutPath</key>
  <string>/var/log/meteorite/output.log</string>
</dict>
</plist>
```

### Managing the Service

```bash
sudo cp com.meteorite.server.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.meteorite.server.plist
sudo launchctl start com.meteorite.server
sudo launchctl stop com.meteorite.server
tail -f /var/log/meteorite/output.log
```

## Supervisor (Cross-Platform)

### Configuration

```ini
; /etc/supervisor/conf.d/meteorite.conf
[program:meteorite]
command=/opt/meteorite/bin/server
directory=/opt/meteorite
user=meteorite
environment=METEORITE_HOST="0.0.0.0",METEORITE_PORT="8080"
autostart=true
autorestart=true
startsecs=5
stopwaitsecs=30
stdout_logfile=/var/log/meteorite/output.log
stderr_logfile=/var/log/meteorite/error.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
```

### Managing the Service

```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start meteorite
sudo supervisorctl status meteorite
sudo supervisorctl tail -f meteorite
```

## Container (Docker)

```dockerfile
FROM scratch
COPY dist/release/bin/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
```

```bash
meteorite build --mode release-static
docker build -t meteorite-app .
docker run -p 8080:8080 meteorite-app
```

## Reverse Proxy (Nginx)

```nginx
upstream meteorite {
  server 127.0.0.1:8080;
  # Or for UNIX socket:
  # server unix:/run/meteorite/meteorite.sock;
}

server {
  listen 80;
  server_name api.example.com;

  location / {
    proxy_pass http://meteorite;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }

  # Serve OpenAPI spec directly from Meteorite
  location /openapi.json {
    proxy_pass http://meteorite/__meteorite/openapi.json;
  }
}
```

## Health Checks

```bash
# Health endpoint
curl http://127.0.0.1:8080/health

# Build info
curl http://127.0.0.1:8080/__meteorite/info

# OpenAPI spec (dev/hybrid mode)
curl http://127.0.0.1:8080/__meteorite/openapi.json
```

## Serverless / Edge

Meteorite is a compiled binary server, not a serverless function runtime.
Serverless/edge deployment is explicitly out of scope for the current release.
Future adapter work could target WASM or edge-compute platforms, but the core
Meteorite compiler focuses on self-contained binary deployments.

`meteorite.release({ adapter = "serverless" })`, `adapter = "edge"`, and
related deployment-adapter spellings fail during release contract validation.
Use the default binary/native adapter and place Meteorite behind your platform's
proxy, CDN, load balancer, or function edge layer when you need edge routing.

If you need edge deployment today, run Meteorite behind an edge proxy or CDN
that forwards to a Meteorite instance deployed via systemd, launchd, or container.
