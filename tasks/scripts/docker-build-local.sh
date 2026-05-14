#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Local build script for aible registry images.
#
# Builds without requiring mise, cargo, or pre-staged Rust binaries by
# compiling the gateway binary inside Docker (BUILD_FROM_SOURCE=1).
#
# Usage:
#   IMAGE_TAG=20260512 tasks/scripts/docker-build-local.sh [gateway|cluster|supervisor|all]
#
# Optional env vars:
#   IMAGE_TAG              Tag to apply (default: dev)
#   GATEWAY_IMAGE          Gateway image name    (default: docker.io/aible/openshell-gateway)
#   CLUSTER_IMAGE          Cluster image name    (default: docker.io/aible/openshell-cluster)
#   SUPERVISOR_IMAGE       Supervisor image name (default: docker.io/aible/openshell-supervisor)
#   CLUSTER_BASE_IMAGE     Upstream cluster base    (default: ghcr.io/nvidia/openshell/cluster:latest)
#   GATEWAY_BASE_IMAGE     Upstream gateway base    (default: ghcr.io/nvidia/openshell/gateway:latest)
#   SUPERVISOR_BASE_IMAGE  Upstream supervisor base (default: ghcr.io/nvidia/openshell/supervisor:latest)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/container-engine.sh"

TARGET="${1:-all}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
GATEWAY_IMAGE="${GATEWAY_IMAGE:-docker.io/aible/openshell-gateway}"
CLUSTER_IMAGE="${CLUSTER_IMAGE:-docker.io/aible/openshell-cluster}"
SUPERVISOR_IMAGE="${SUPERVISOR_IMAGE:-docker.io/aible/openshell-supervisor}"
CLUSTER_BASE_IMAGE="${CLUSTER_BASE_IMAGE:-ghcr.io/nvidia/openshell/cluster:latest}"
# Supervisor base: debian-slim provides glibc + ld-linux for our dynamically
# linked openshell-sandbox binary. The upstream image is FROM scratch (their
# binary is statically linked), so we can't use it as a base for ours. We use
# trixie (Debian 13) for mainline security support; glibc is forward-compatible
# so the bookworm-built binary (glibc 2.36) runs fine on trixie (glibc 2.41).
SUPERVISOR_BASE_IMAGE="${SUPERVISOR_BASE_IMAGE:-debian:trixie-slim}"

build_gateway() {
    echo "=== Building gateway: ${GATEWAY_IMAGE}:${IMAGE_TAG} ==="
    GATEWAY_BASE_IMAGE="${GATEWAY_BASE_IMAGE:-ghcr.io/nvidia/openshell/gateway:latest}"
    ce_build \
        -f "${ROOT}/deploy/docker/Dockerfile.gateway" \
        --build-arg BASE_IMAGE="${GATEWAY_BASE_IMAGE}" \
        -t "${GATEWAY_IMAGE}:${IMAGE_TAG}" \
        --provenance=false \
        --load \
        "${ROOT}"
    echo "Gateway image ready: ${GATEWAY_IMAGE}:${IMAGE_TAG}"
}

build_cluster() {
    echo "=== Packaging inner Helm chart ==="
    local chart_stage="${ROOT}/deploy/docker/.build/charts"
    mkdir -p "${chart_stage}"
    helm package "${ROOT}/deploy/helm/openshell" \
        --version 0.1.0 \
        --destination "${chart_stage}" \
        --dependency-update=false \
        2>&1
    local chart_tgz="${chart_stage}/helm-chart-0.1.0.tgz"
    local target_tgz="${chart_stage}/openshell-0.1.0.tgz"
    [[ -f "${chart_tgz}" && "${chart_tgz}" != "${target_tgz}" ]] && mv "${chart_tgz}" "${target_tgz}"
    echo "Staged: ${target_tgz} ($(wc -c < "${target_tgz}") bytes)"

    echo "=== Building cluster: ${CLUSTER_IMAGE}:${IMAGE_TAG} ==="
    ce_build \
        -f "${ROOT}/deploy/docker/Dockerfile.cluster" \
        --build-arg BASE_IMAGE="${CLUSTER_BASE_IMAGE}" \
        -t "${CLUSTER_IMAGE}:${IMAGE_TAG}" \
        --provenance=false \
        --load \
        "${ROOT}"
    echo "Cluster image ready: ${CLUSTER_IMAGE}:${IMAGE_TAG}"
}

build_supervisor() {
    echo "=== Building supervisor: ${SUPERVISOR_IMAGE}:${IMAGE_TAG} ==="
    ce_build \
        -f "${ROOT}/deploy/docker/Dockerfile.supervisor" \
        --build-arg BASE_IMAGE="${SUPERVISOR_BASE_IMAGE}" \
        -t "${SUPERVISOR_IMAGE}:${IMAGE_TAG}" \
        --provenance=false \
        --load \
        "${ROOT}"
    echo "Supervisor image ready: ${SUPERVISOR_IMAGE}:${IMAGE_TAG}"
}

case "${TARGET}" in
    gateway)    build_gateway ;;
    cluster)    build_cluster ;;
    supervisor) build_supervisor ;;
    all)        build_gateway; build_supervisor; build_cluster ;;
    *)
        echo "Usage: $0 [gateway|cluster|supervisor|all]" >&2
        exit 1
        ;;
esac
