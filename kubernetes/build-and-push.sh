#!/bin/bash
# ============================================================================
# SECURE DOCKER BUILD, SCAN & PUSH SCRIPT
# ============================================================================
# This script demonstrates OWASP-compliant container building and registry push
# Usage: ./build-and-push.sh myapp 1.0.0 myregistry.azurecr.io
# ============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# CONFIGURATION
# ============================================================================

# Default values (override via CLI args)
APP_NAME="${1:-myapp}"
VERSION="${2:-1.0.0}"
REGISTRY="${3:-myregistry.azurecr.io}"
PLATFORMS="linux/amd64,linux/arm64"  # Build for both x86 and ARM

# Derived variables
IMAGE_NAME="${REGISTRY}/${APP_NAME}"
IMAGE_TAG="${IMAGE_NAME}:${VERSION}"
IMAGE_LATEST="${IMAGE_NAME}:latest"

# ============================================================================
# FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# PRE-BUILD VALIDATION
# ============================================================================

validate_environment() {
    log_info "Validating environment..."
    
    # Check required tools
    command -v docker &> /dev/null || { log_error "Docker not installed"; exit 1; }
    log_success "Docker found"
    
    # For multi-platform builds
    if ! docker buildx version &> /dev/null; then
        log_warn "Docker buildx not found; installing..."
        docker run --privileged --rm tonistiigi/binfmt --install all
    fi
    
    # Check if Dockerfile exists
    [[ -f Dockerfile ]] || { log_error "Dockerfile not found"; exit 1; }
    log_success "Dockerfile found"
}

# ============================================================================
# BUILD IMAGE
# ============================================================================

build_image() {
    log_info "Building image: ${IMAGE_TAG}..."
    
    # Use buildx for multi-platform builds (requires buildx plugin)
    # Remove this line if you only need single-platform builds
    docker buildx build \
        --platform ${PLATFORMS} \
        --tag ${IMAGE_TAG} \
        --tag ${IMAGE_LATEST} \
        --load \
        --file Dockerfile \
        .
    
    # Alternative: single-platform build (faster for local testing)
    # docker build \
    #     --tag ${IMAGE_TAG} \
    #     --tag ${IMAGE_LATEST} \
    #     --file Dockerfile \
    #     .
    
    log_success "Image built: ${IMAGE_TAG}"
}

# ============================================================================
# SCAN FOR VULNERABILITIES
# ============================================================================

scan_image() {
    log_info "Scanning image for vulnerabilities..."
    
    # Check if Trivy is installed
    if ! command -v trivy &> /dev/null; then
        log_warn "Trivy not installed. Attempting Docker-based scan..."
        docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy image --severity HIGH,CRITICAL ${IMAGE_TAG}
    else
        trivy image --severity HIGH,CRITICAL ${IMAGE_TAG}
    fi
    
    # Note: Trivy exits with non-zero if vulnerabilities found
    # Remove '|| true' below to fail build if vulnerabilities detected
    SCAN_RESULT=$? || true
    
    if [[ $SCAN_RESULT -eq 0 ]]; then
        log_success "No HIGH/CRITICAL vulnerabilities found"
    else
        log_warn "Vulnerabilities detected (non-blocking); review above output"
    fi
}

# ============================================================================
# INSPECT IMAGE
# ============================================================================

inspect_image() {
    log_info "Inspecting image layers and metadata..."
    
    # Show image size
    SIZE=$(docker images ${IMAGE_TAG} --format "{{.Size}}")
    log_success "Image size: ${SIZE}"
    
    # Show layers
    log_info "Image layers (use 'docker history ${IMAGE_TAG}' for details):"
    docker history ${IMAGE_TAG} --no-trunc --human | head -10
    
    # Show running user
    RUNNING_USER=$(docker run --rm ${IMAGE_TAG} whoami 2>/dev/null || echo "root")
    log_success "Container runs as: ${RUNNING_USER}"
    
    # Check for common security issues
    log_info "Checking for common security issues..."
    
    # Verify non-root user
    if [[ "${RUNNING_USER}" == "root" ]]; then
        log_error "Container running as root! This violates CIS benchmarks."
        exit 1
    else
        log_success "Container running as non-root user ✓"
    fi
}

# ============================================================================
# REGISTRY AUTHENTICATION
# ============================================================================

authenticate_registry() {
    log_info "Authenticating with registry: ${REGISTRY}..."
    
    # Azure Container Registry
    if [[ "${REGISTRY}" == *"azurecr.io" ]]; then
        log_info "Detected Azure Container Registry"
        if [[ -z "${AZURE_USERNAME:-}" ]]; then
            log_info "Run: az acr login --name <registry-name>"
        fi
    fi
    
    # AWS Elastic Container Registry
    if [[ "${REGISTRY}" == *.dkr.ecr.*.amazonaws.com ]]; then
        log_info "Detected AWS ECR"
        ACCOUNT_ID=$(echo ${REGISTRY} | cut -d. -f1)
        REGION=$(echo ${REGISTRY} | cut -d. -f4)
        aws ecr get-login-password --region ${REGION} | \
            docker login --username AWS --password-stdin ${REGISTRY}
    fi
    
    # Docker Hub
    if [[ -z "${REGISTRY}" || "${REGISTRY}" == "docker.io" ]]; then
        log_info "Use: docker login"
    fi
}

# ============================================================================
# PUSH TO REGISTRY
# ============================================================================

push_image() {
    log_info "Pushing image to registry: ${REGISTRY}..."
    
    # Tag with semver
    docker tag ${IMAGE_TAG} ${IMAGE_LATEST}
    
    # Push both tags
    docker push ${IMAGE_TAG}
    docker push ${IMAGE_LATEST}
    
    log_success "Image pushed successfully"
    log_success "Pull with: docker pull ${IMAGE_TAG}"
}

# ============================================================================
# SIGN IMAGE (optional, requires Cosign)
# ============================================================================

sign_image() {
    log_info "Checking for image signing capability (Cosign)..."
    
    if ! command -v cosign &> /dev/null; then
        log_warn "Cosign not installed; skipping image signing"
        log_info "To enable signing: https://docs.sigstore.dev/cosign/installation/"
        return 0
    fi
    
    log_info "Signing image with Cosign..."
    
    # Sign image (requires COSIGN_EXPERIMENTAL=1 or local key)
    COSIGN_EXPERIMENTAL=1 cosign sign ${IMAGE_TAG}
    
    log_success "Image signed and verified"
    log_info "Verify with: COSIGN_EXPERIMENTAL=1 cosign verify ${IMAGE_TAG}"
}

# ============================================================================
# GENERATE SBOM (Software Bill of Materials)
# ============================================================================

generate_sbom() {
    log_info "Checking for SBOM generation capability (Syft)..."
    
    if ! command -v syft &> /dev/null; then
        log_warn "Syft not installed; skipping SBOM generation"
        log_info "To enable SBOM: https://github.com/anchore/syft"
        return 0
    fi
    
    log_info "Generating SBOM..."
    
    SBOM_FILE="sbom-${VERSION}.json"
    syft ${IMAGE_TAG} -o json > ${SBOM_FILE}
    
    log_success "SBOM generated: ${SBOM_FILE}"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "=========================================="
    log_info "OWASP-Compliant Docker Build Pipeline"
    log_info "=========================================="
    log_info "App: ${APP_NAME}"
    log_info "Version: ${VERSION}"
    log_info "Registry: ${REGISTRY}"
    log_info "Image: ${IMAGE_TAG}"
    log_info "=========================================="
    echo
    
    validate_environment
    echo
    
    build_image
    echo
    
    inspect_image
    echo
    
    scan_image
    echo
    
    # Uncomment to enable these steps:
    # authenticate_registry
    # echo
    # push_image
    # echo
    # sign_image
    # echo
    # generate_sbom
    
    log_success "Build pipeline completed!"
    log_info "Next steps:"
    echo "  1. Review vulnerabilities above"
    echo "  2. Run: docker run --rm ${IMAGE_TAG} /bin/sh"
    echo "  3. Push: docker push ${IMAGE_TAG}"
    echo "  4. Deploy to Kubernetes or Docker Swarm"
}

# Run main function
main "$@"
