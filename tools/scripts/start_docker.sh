#!/bin/bash
set -e

echo "Checking Docker daemon..."

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is required but the docker command was not found." >&2
  echo "Install Docker Desktop and make sure docker is on your PATH." >&2
  exit 1
fi

# Works on any OS, including WezTerm / Git Bash on Windows.
if docker info > /dev/null 2>&1; then
  echo "Docker is already running."
  exit 0
fi

case "$(uname -s)" in
  Darwin)
    echo "Docker is not running. Attempting to start Docker Desktop..."
    open -a Docker

    echo -n "Waiting for Docker to initialize"
    until docker info > /dev/null 2>&1; do
      echo -n "."
      sleep 2
    done

    echo -e "\nDocker started successfully!"
    ;;
  Linux)
    if ! command -v systemctl >/dev/null 2>&1; then
      echo "ERROR: Docker is not running and systemctl is unavailable." >&2
      exit 1
    fi

    echo "Docker is not running. Attempting to start Docker Engine..."
    if ! sudo systemctl start docker; then
      echo "ERROR: Failed to start Docker Engine with systemctl." >&2
      exit 1
    fi

    echo -n "Waiting for Docker to initialize"
    attempts=0
    until docker info > /dev/null 2>&1; do
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

    echo -e "\nDocker started successfully!"
    ;;
  *)
    echo "ERROR: Docker is installed but not running." >&2
    echo 'On Windows, start "C:\Program Files\Docker\Docker\Docker Desktop.exe", wait until it is ready, then try again.' >&2
    exit 1
    ;;
esac
