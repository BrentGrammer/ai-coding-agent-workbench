#!/bin/bash
set -e

echo "Checking Docker daemon..."

case "$(uname -s)" in
  Darwin)
    if docker info > /dev/null 2>&1; then
      echo "✅ Docker is already running."
      exit 0
    fi

    echo "Docker is not running. Attempting to start Docker Desktop..."
    echo 'If on Windows, quit this script and run: "C:\Program Files\Docker\Docker\Docker Desktop.exe"'
    open -a Docker

    echo -n "Waiting for Docker to initialize"
    until docker info > /dev/null 2>&1; do
      echo -n "."
      sleep 2
    done

    echo -e "\n✅ Docker started successfully!"
    ;;
  Linux)
    if ! command -v docker >/dev/null 2>&1; then
      echo "ERROR: Docker Engine is required but the docker command was not found." >&2
      exit 1
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
      echo "ERROR: Docker is not running and systemctl is unavailable." >&2
      exit 1
    fi

    if systemctl is-active --quiet docker.service || systemctl is-active --quiet docker.socket; then
      echo "✅ Docker is already running."
      exit 0
    fi

    echo "Docker is not running. Attempting to start Docker Engine..."
    if ! sudo systemctl start docker; then
      echo "ERROR: Failed to start Docker Engine with systemctl." >&2
      exit 1
    fi

    echo -n "Waiting for Docker to initialize"
    attempts=0
    until systemctl is-active --quiet docker.service || systemctl is-active --quiet docker.socket; do
      attempts=$((attempts + 1))
      if [ "$attempts" -ge 30 ]; then
        echo >&2
        echo "ERROR: Docker Engine did not become ready within 60 seconds." >&2
        echo "Run 'systemctl status docker' for details." >&2
        exit 1
      fi
      echo -n "."
      sleep 2
    done

    echo -e "\n✅ Docker started successfully!"
    ;;
  *)
    echo "ERROR: Automatic Docker startup is not supported on this operating system." >&2
    echo 'On Windows, start "C:\Program Files\Docker\Docker\Docker Desktop.exe" first.' >&2
    exit 1
    ;;
esac
