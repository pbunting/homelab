#!/bin/bash

# Launch core services on Docker

# Check Docker is running.
docker info 2>&1 >/dev/null || (echo "Docker is not running. Start Docker."; exit 1)

# Check VMan is available

# Run the OTel stack and the BuildKite agent using Docker Compose.
docker compose up

# Launch VMs and run Kubernetes on VMs

