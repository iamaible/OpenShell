#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Aible fork build script for gateway and supervisor images.
#
# Compiles the Rust binaries inside Docker (multi-stage build) so no local
# Rust toolchain or pre-staged binaries are required.  Supports single-arch
# local builds (--load) and multi-arch cloud builds (--push via buildx).
#
# Usage:
#   IMAGE_TAG=20260607 tasks/scripts/docker-build-local.sh [gateway|supervisor|all]
#
# Optional env vars:
#   IMAGE_TAG              Tag to apply (default: dev)
#   PLATFORM               Target platform(s) (default: linux/arm64)
#                          Multi-arch: linux/amd64,linux/arm64
#   PUSH                   Set to 1 to push instead of loading locally (required
#                          for multi-arch builds — buildx cannot --load multi-arch)
#   DOCKER_BUILDER         buildx builder name for Docker Build Cloud
#                          (e.g. cloud-aible-aible-cloud-builder)
#   GATEWAY_IMAGE          Gateway image name    (default: docker.io/aible/openshell-gateway)
#   SUPERVISOR_IMAGE       Supervisor image name (default: docker.io/aible/openshell-supervisor)
#   GATEWAY_BASE_IMAGE     Upstream gateway base (default: ghcr.io/nvidia/openshell/gateway:latest)
#   SUPERVISOR_BASE_IMAGE  Supervisor base image (default: debian:trixie-slim)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/container-engine.sh"

TARGET="${1:-all}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
PLATFORM="${PLATFORM:-linux/arm64}"
PUSH="${PUSH:-0}"
GATEWAY_IMAGE="${GATEWAY_IMAGE:-docker.io/aible/openshell-gateway}"
SUPERVISOR_IMAGE="${SUPERVISOR_IMAGE:-docker.io/aible/openshell-supervisor}"
GATEWAY_BASE_IMAGE="${GATEWAY_BASE_IMAGE:-ghcr.io/nvidia/openshell/gateway:latest}"
SUPERVISOR_BASE_IMAGE="${SUPERVISOR_BASE_IMAGE:-debian:trixie-slim}"

# Determine output mode: multi-arch requires --push; single-arch defaults to --load.
if [[ "${PUSH}" == "1" ]] || [[ "${PLATFORM}" == *","* ]]; then
    OUTPUT_FLAG="--push"
else
    OUTPUT_FLAG="--load"
fi

# Inject cloud builder if specified.
BUILDER_FLAG=()
if [[ -n "${DOCKER_BUILDER:-}" ]]; then
    BUILDER_FLAG=(--builder "${DOCKER_BUILDER}")
fi

build_gateway() {
    echo "=== Building gateway: ${GATEWAY_IMAGE}:${IMAGE_TAG} [${PLATFORM}] ==="
    ce_build \
        "${BUILDER_FLAG[@]}" \
        -f "${ROOT}/deploy/docker/Dockerfile.gateway" \
        --build-arg BASE_IMAGE="${GATEWAY_BASE_IMAGE}" \
        --platform "${PLATFORM}" \
        -t "${GATEWAY_IMAGE}:${IMAGE_TAG}" \
        --provenance=false \
        "${OUTPUT_FLAG}" \
        "${ROOT}"
    echo "Gateway image ready: ${GATEWAY_IMAGE}:${IMAGE_TAG}"
}

build_supervisor() {
    echo "=== Building supervisor: ${SUPERVISOR_IMAGE}:${IMAGE_TAG} [${PLATFORM}] ==="
    ce_build \
        "${BUILDER_FLAG[@]}" \
        -f "${ROOT}/deploy/docker/Dockerfile.supervisor" \
        --build-arg BASE_IMAGE="${SUPERVISOR_BASE_IMAGE}" \
        --platform "${PLATFORM}" \
        -t "${SUPERVISOR_IMAGE}:${IMAGE_TAG}" \
        --provenance=false \
        "${OUTPUT_FLAG}" \
        "${ROOT}"
    echo "Supervisor image ready: ${SUPERVISOR_IMAGE}:${IMAGE_TAG}"
}

case "${TARGET}" in
    gateway)    build_gateway ;;
    supervisor) build_supervisor ;;
    all)        build_gateway; build_supervisor ;;
    *)
        echo "Usage: $0 [gateway|supervisor|all]" >&2
        exit 1
        ;;
esac
