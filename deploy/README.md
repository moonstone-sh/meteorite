# Meteorite Container Deployment

This recipe packages an already-built Meteorite release directory. Build the release first, then use `dist/release` as the Docker build context so source files, `.moonstone/env`, graph caches, and host paths are not sent to Docker.

```bash
moon run release
python3 -m json.tool dist/release/meteorite-release.json >/dev/null

docker build \
  -f deploy/Dockerfile.release \
  -t my-meteorite-app:latest \
  dist/release

docker run --rm -p 8080:8080 my-meteorite-app:latest
curl -fsS http://127.0.0.1:8080/__meteorite/info
```

## Contract

- Context must be `dist/release`, not the repository root.
- Image copies only the deployable release tree into `/app`.
- Container runs as the unprivileged `meteorite` user.
- `GET /__meteorite/info` exposes safe build facts and must not include host source paths.
- For Linux containers, build or release a Linux-compatible `bin/server` before `docker build`.
