# Run the transit backend in Docker

The container runs FastAPI only. iOS and watchOS apps still build in Xcode. No database or persistent volume is needed: static schedules and realtime feeds are cached in process memory, and restarting the container clears those caches. Outbound HTTPS to Rutgers TripShot is required.

## Prerequisites

Install/start a Docker-compatible engine (Docker Desktop or Colima). On the development machine, the Docker CLI is installed and points at Colima, but the engine was not running when this setup was added. If you already use Colima, run `colima start`. Confirm `docker info` succeeds. Docker Compose is optional; its plugin was not available on this machine.

Run commands from the repository directory containing Dockerfile:

```sh
cd "/Users/jrrohit/Documents/Rutgers Bussing/Rutgers Bussing"
docker build -t rutgers-transit:local .
docker run -d --name rutgers-transit -p 127.0.0.1:8001:8000 rutgers-transit:local
```

Port **8001** avoids the existing non-container backend on port 8000. Check:

```sh
curl --fail http://localhost:8001/health
curl --fail http://localhost:8001/catalog
docker logs --tail 50 rutgers-transit
docker inspect --format='{{.State.Health.Status}}' rutgers-transit
```

Health checks verify that the process responds, not that TripShot is available. Open `http://localhost:8001/docs`, select a route and one of its stop IDs from `/catalog`, then call `/arrivals`. Confirm `source` is `live` and `updatedAt` is recent. Empty predictions may be a valid response.

In iPhone Simulator, choose **Live arrivals → Data source**, set `http://localhost:8001`. Destination/transfer planning is unavailable pending live integration.

For a physical phone on the same network, publish on all host interfaces instead:

```sh
docker run -d --name rutgers-transit-phone -p 8001:8000 rutgers-transit:local
```

Stop the first container before using the same host port. Set the phone endpoint to `http://YOUR-MAC-NAME.local:8001`, allow local network access, and ensure the Mac firewall permits the port. This exposes the development API on your local network. A Colima installation may also need its host port-forwarding configuration to allow LAN access.

## Optional Compose

If the Compose plugin is installed:

```sh
docker compose up --build -d
docker compose logs -f api
docker compose down
```

Compose defaults to loopback port 8001. To allow a physical phone:

```sh
API_BIND_ADDRESS=0.0.0.0 docker compose up --build -d
```

Don't run Compose and a standalone container on the same host port simultaneously.

## Stop and rebuild

```sh
docker stop rutgers-transit
docker rm rutgers-transit
docker build -t rutgers-transit:local .
docker run -d --name rutgers-transit -p 127.0.0.1:8001:8000 rutgers-transit:local
```

Removing this container discards only its in-memory cache. It doesn't delete app preferences stored on the phone.

## Azure deployment

Azure Container Apps can host this API image directly, with HTTP ingress targeting container port 8000 and an HTTPS endpoint for the app. Build for the architecture supported by your chosen Azure environment; don't assume a Mac ARM image will run on an x86 host. Store the built image in a registry, configure Azure health probes separately, and add shared schedule caching before scaling to multiple replicas. No Azure resources are created by these files.

The image runs as a non-root user. The build context allowlist excludes Git history, virtual environments, credentials, tests, and Apple app sources. Runtime dependency versions are pinned directly; base-image digest and transitive dependency locking can be added for release builds.

## Validation status

Container build and smoke tests require a running Docker engine. They could not be performed when this configuration was added because the configured Colima engine was stopped. Do not treat the existing native Python server checks as a container test.
