# ComfyUI Docker

Run [ComfyUI](https://github.com/comfy-org/ComfyUI) on Linux in Docker with NVIDIA GPU acceleration.

This image is built on NVIDIA CUDA and includes a custom PyTorch stack intended to remain compatible with older AVX-capable CPUs while still using CUDA for GPU workloads.

A prebuilt image is published to GitHub Container Registry (GHCR):

```text
ghcr.io/reganchan/comfyui_docker:latest
```

## Features

- ComfyUI running in an NVIDIA CUDA container
- NVIDIA GPU passthrough with the NVIDIA Container Toolkit
- Persistent directories for models, custom nodes, inputs, outputs, user data, and Python user packages
- ComfyUI Manager enabled
- Hugging Face CLI included
- Prebuilt image published automatically to GHCR
- Local Docker build remains available when you need to modify the image

## Requirements

This project is intended for **Linux hosts with an NVIDIA GPU**.

You need:

- A supported NVIDIA GPU
- NVIDIA drivers installed on the Linux host
- Docker Engine with Docker Compose
- NVIDIA Container Toolkit

Verify that the host can see the GPU:

```bash
nvidia-smi
```

## Install Docker

On Ubuntu/Debian, install Docker Engine by following Docker's official instructions:

https://docs.docker.com/engine/install/

After installation, verify Docker:

```bash
docker --version
docker compose version
```

If you want to run Docker without `sudo`, add your user to the `docker` group:

```bash
sudo usermod -aG docker "$USER"
```

Log out and back in for the group change to take effect.

## Install NVIDIA Container Toolkit

First make sure the NVIDIA driver is installed and `nvidia-smi` works on the host.

For Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg2

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
```

Configure Docker to use the NVIDIA runtime:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Test GPU access from Docker:

```bash
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

If that command displays your GPU, Docker GPU passthrough is working.

## Quick Start

Clone the repository:

```bash
git clone https://github.com/reganchan/comfyui_docker.git
cd comfyui_docker
```

Create the persistent directories:

```bash
mkdir -p custom_nodes models input output user local
```

Pull the latest prebuilt image:

```bash
docker compose pull
```

Start ComfyUI:

```bash
docker compose up -d
```

Open:

```text
http://localhost:8188
```

View logs:

```bash
docker compose logs -f comfyui
```

Stop the container:

```bash
docker compose down
```

## Updating

The `latest` image is rebuilt and published when changes are pushed to the `master` branch.

To update your local installation:

```bash
docker compose pull
docker compose up -d
```

To force recreation after pulling:

```bash
docker compose up -d --force-recreate
```

Your mounted data directories remain on the host and are not removed when the container is recreated.

## Persistent Data

The default Compose configuration mounts:

| Host directory | Container directory | Purpose |
| --- | --- | --- |
| `./custom_nodes` | `/home/comfy/ComfyUI/custom_nodes` | ComfyUI custom nodes |
| `./models` | `/home/comfy/ComfyUI/models` | Checkpoints, VAEs, LoRAs, etc. |
| `./input` | `/home/comfy/ComfyUI/input` | Input files |
| `./output` | `/home/comfy/ComfyUI/output` | Generated files |
| `./user` | `/home/comfy/ComfyUI/user` | ComfyUI user data and workflows |
| `./local` | `/home/comfy/.local` | User-level Python packages/data |

Because these directories are bind-mounted, their contents survive image updates and container recreation.

## GPU Selection

By default, the Compose file exposes all available NVIDIA GPUs to ComfyUI.

To expose only a specific GPU, replace:

```yaml
count: all
```

with:

```yaml
device_ids: ["0"]
```

For example, to expose GPU 1 only:

```yaml
device_ids: ["1"]
```

Do not specify both `count` and `device_ids`.

## Build Locally

The normal `docker-compose.yml` uses the prebuilt GHCR image.

If you modify the Dockerfile and want to build locally instead:

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml build
docker compose -f docker-compose.yml -f docker-compose.build.yml up -d
```

To rebuild completely without cache:

```bash
docker compose -f docker-compose.yml -f docker-compose.build.yml build --no-cache
```

The Dockerfile currently builds a custom PyTorch/CUDA stack from source, so a clean build can be CPU-, disk-, and time-intensive.

## Pull the Image Directly

You can also use Docker without Compose:

```bash
docker pull ghcr.io/reganchan/comfyui_docker:latest
```

For tagged releases:

```bash
docker pull ghcr.io/reganchan/comfyui_docker:v1.0.0
```

## GitHub Container Registry

Images are published by GitHub Actions to:

```text
ghcr.io/reganchan/comfyui_docker
```

The workflow publishes:

- `latest` for the default branch
- branch-name tags
- Git tag/version tags such as `v1.0.0`
- commit SHA tags

The workflow uses GitHub's built-in `GITHUB_TOKEN`; no separate GHCR password is required.

After the package is published for the first time, check the package settings on GitHub and make the package **Public** if you want unauthenticated users/hosts to be able to pull it.

If the package is private, authenticate first:

```bash
echo "$CR_PAT" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

The token must have permission to read packages.

## GitHub Actions

The publishing workflow lives at:

```text
.github/workflows/docker-publish.yml
```

It runs when:

- a commit is pushed to `master`
- a Git tag beginning with `v` is pushed
- it is started manually with `workflow_dispatch`

The job builds the `comfyui` target from the Dockerfile and pushes the resulting image to GHCR.

### Important build note

This repository compiles PyTorch and related packages from source. That is substantially heavier than a typical Docker build and may exceed the CPU, disk, cache, or execution limits of a GitHub-hosted runner.

If that happens, the workflow itself does not need to change much; the most reliable solution is to use a sufficiently powerful **self-hosted GitHub Actions runner** and change:

```yaml
runs-on: ubuntu-latest
```

to:

```yaml
runs-on: self-hosted
```

## Image Details

The Dockerfile currently uses CUDA 12.9.2 on Ubuntu 22.04 and builds the final `comfyui` target with ComfyUI listening on:

```text
0.0.0.0:8188
```

The image starts ComfyUI with Manager enabled.

## Troubleshooting

### Docker cannot access the GPU

Verify the host first:

```bash
nvidia-smi
```

Then verify Docker:

```bash
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

If the host command works but the Docker command does not, reconfigure the runtime:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Check the running container

```bash
docker compose ps
docker compose logs -f comfyui
```

### Check GPU visibility inside ComfyUI

```bash
docker compose exec comfyui nvidia-smi
```

### Permission problems in mounted directories

The published image is built with UID/GID `1000:1000` by default.

If your Linux user uses different IDs, either adjust ownership of the persistent directories or build the image locally with your own UID/GID using `docker-compose.build.yml`.

Check your IDs:

```bash
id -u
id -g
```

## Disclaimer

This is a personal Docker setup for running ComfyUI. It is not an official ComfyUI or NVIDIA image.

ComfyUI, PyTorch, NVIDIA CUDA, and included third-party components are subject to their respective licenses.
