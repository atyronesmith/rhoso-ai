#!/bin/bash
# validate-kustomize.sh - Validate and test Kustomize configurations

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUSTOMIZE_DIR="${SCRIPT_DIR}/kustomize"
TEMP_DIR="${SCRIPT_DIR}/.kustomize-temp"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $*"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local tools=("kubectl" "kustomize" "yq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed"
            return 1
        fi
    done

    # Check kubectl version supports kustomize
    if ! kubectl kustomize --help &> /dev/null; then
        log_error "kubectl doesn't support kustomize (version too old?)"
        return 1
    fi

    log_info "Prerequisites check passed"
}

# Validate base configuration
validate_base() {
    log_info "Validating base configuration..."

    if [[ ! -d "${KUSTOMIZE_DIR}/base" ]]; then
        log_error "Base directory not found: ${KUSTOMIZE_DIR}/base"
        return 1
    fi

    # Try to build base
    log_debug "Building base configuration..."
    if kubectl kustomize "${KUSTOMIZE_DIR}/base" > /dev/null 2>&1; then
        log_info "Base configuration is valid"
    else
        log_error "Failed to build base configuration"
        kubectl kustomize "${KUSTOMIZE_DIR}/base" 2>&1 | tail -20
        return 1
    fi
}

# Validate overlays
validate_overlays() {
    log_info "Validating overlays..."

    local overlays_dir="${KUSTOMIZE_DIR}/overlays"
    if [[ ! -d "$overlays_dir" ]]; then
        log_warn "No overlays directory found"
        return 0
    fi

    local errors=0
    for overlay in "$overlays_dir"/*; do
        if [[ -d "$overlay" ]]; then
            local env_name
            env_name=$(basename "$overlay")
            log_debug "Validating overlay: $env_name"

            if kubectl kustomize "$overlay" > /dev/null 2>&1; then
                log_info "Overlay '$env_name' is valid"
            else
                log_error "Failed to build overlay '$env_name'"
                kubectl kustomize "$overlay" 2>&1 | tail -10
                ((errors++))
            fi
        fi
    done

    return "$errors"
}

# Check for required resources
check_required_resources() {
    log_info "Checking for required resources..."

    local env="${1:-production}"
    local overlay_dir="${KUSTOMIZE_DIR}/overlays/${env}"

    mkdir -p "$TEMP_DIR"
    kubectl kustomize "$overlay_dir" > "$TEMP_DIR/rendered.yaml"

    # Required resource types
    local required_resources=(
        "OpenStackControlPlane"
        "OpenStackDataPlaneNodeSet"
        "NetworkAttachmentDefinition"
        "IPAddressPool"
        "L2Advertisement"
        "NetConfig"
        "Secret"
    )

    local missing=0
    for resource in "${required_resources[@]}"; do
        if ! grep -q "kind: $resource" "$TEMP_DIR/rendered.yaml"; then
            log_error "Missing required resource: $resource"
            ((missing++))
        else
            log_info "Found required resource: $resource"
        fi
    done

    rm -rf "$TEMP_DIR"
    return "$missing"
}

# Validate network configuration
validate_networks() {
    log_info "Validating network configuration..."

    local env="${1:-production}"
    local overlay_dir="${KUSTOMIZE_DIR}/overlays/${env}"

    mkdir -p "$TEMP_DIR"
    kubectl kustomize "$overlay_dir" > "$TEMP_DIR/rendered.yaml"

    # Extract NetConfig
    yq eval-all 'select(.kind == "NetConfig")' "$TEMP_DIR/rendered.yaml" > "$TEMP_DIR/netconfig.yaml"

    if [[ ! -s "$TEMP_DIR/netconfig.yaml" ]]; then
        log_error "No NetConfig found in rendered output"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Check for required networks
    local required_networks=("CtlPlane" "InternalApi" "Storage" "Tenant")
    local errors=0

    for network in "${required_networks[@]}"; do
        if yq eval ".spec.networks[].name | select(. == \"$network\")" "$TEMP_DIR/netconfig.yaml" | grep -q "$network"; then
            log_info "Found required network: $network"
        else
            log_error "Missing required network: $network"
            ((errors++))
        fi
    done

    # Check for CIDR conflicts
    log_debug "Checking for CIDR conflicts..."
    local cidrs
    cidrs=$(yq eval '.spec.networks[].subnets[].cidr' "$TEMP_DIR/netconfig.yaml" | sort)
    local conflicts
    conflicts=$(echo "$cidrs" | uniq -d)

    if [[ -n "$conflicts" ]]; then
        log_error "CIDR conflicts detected:"
        echo "$conflicts"
        ((errors++))
    fi

    rm -rf "$TEMP_DIR"
    return "$errors"
}

# Check resource limits and requests
check_resource_limits() {
    log_info "Checking resource limits and requests..."

    local env="${1:-production}"
    local overlay_dir="${KUSTOMIZE_DIR}/overlays/${env}"

    mkdir -p "$TEMP_DIR"
    kubectl kustomize "$overlay_dir" > "$TEMP_DIR/rendered.yaml"

    # Extract OpenStackControlPlane
    yq eval-all 'select(.kind == "OpenStackControlPlane")' "$TEMP_DIR/rendered.yaml" > "$TEMP_DIR/controlplane.yaml"

    if [[ -s "$TEMP_DIR/controlplane.yaml" ]]; then
        # Check storage class
        local storage_class
        storage_class=$(yq eval '.spec.storageClass' "$TEMP_DIR/controlplane.yaml")
        if [[ "$storage_class" == "null" || -z "$storage_class" ]]; then
            log_warn "No storage class specified in control plane"
        else
            log_info "Storage class: $storage_class"
        fi

        # Check replica counts
        log_debug "Checking service replica counts..."
        local services=("keystone" "nova" "neutron" "cinder" "glance")
        for service in "${services[@]}"; do
            local replicas
            replicas=$(yq eval ".spec.$service.template.replicas // .spec.$service.template.*.replicas" "$TEMP_DIR/controlplane.yaml" 2>/dev/null | grep -v null | head -1)
            if [[ -n "$replicas" && "$replicas" != "null" ]]; then
                log_info "$service replicas: $replicas"
            fi
        done
    fi

    rm -rf "$TEMP_DIR"
}

# Dry run against cluster
dry_run_apply() {
    log_info "Performing dry-run apply..."

    local env="${1:-production}"
    local overlay_dir="${KUSTOMIZE_DIR}/overlays/${env}"

    if ! oc auth can-i create deployment --namespace openstack &> /dev/null; then
        log_warn "No cluster access or insufficient permissions for dry-run"
        return 0
    fi

    log_debug "Running kubectl apply --dry-run..."
    if kubectl apply -k "$overlay_dir" --dry-run=client -o yaml > /dev/null 2>&1; then
        log_info "Dry-run apply successful"
    else
        log_error "Dry-run apply failed"
        kubectl apply -k "$overlay_dir" --dry-run=client 2>&1 | tail -20
        return 1
    fi
}

# Generate diff between environments
generate_diff() {
    log_info "Generating diff between environments..."

    local env1="${1:-development}"
    local env2="${2:-production}"

    mkdir -p "$TEMP_DIR"

    log_debug "Building $env1..."
    kubectl kustomize "${KUSTOMIZE_DIR}/overlays/${env1}" > "$TEMP_DIR/${env1}.yaml" 2>/dev/null

    log_debug "Building $env2..."
    kubectl kustomize "${KUSTOMIZE_DIR}/overlays/${env2}" > "$TEMP_DIR/${env2}.yaml" 2>/dev/null

    log_info "Differences between $env1 and $env2:"
    diff -u "$TEMP_DIR/${env1}.yaml" "$TEMP_DIR/${env2}.yaml" | head -50 || true

    rm -rf "$TEMP_DIR"
}

# Generate report
generate_report() {
    log_info "Generating validation report..."

    local env="${1:-production}"
    local report_file="kustomize-validation-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "Kustomize Validation Report"
        echo "=========================="
        echo "Generated: $(date)"
        echo "Environment: $env"
        echo ""

        echo "Directory Structure:"
        echo "-------------------"
        find "${KUSTOMIZE_DIR}" -type f -name "kustomization.yaml" | sort
        echo ""

        echo "Resource Summary:"
        echo "----------------"
        kubectl kustomize "${KUSTOMIZE_DIR}/overlays/${env}" 2>/dev/null | grep "^kind:" | sort | uniq -c
        echo ""

        echo "Images:"
        echo "-------"
        kubectl kustomize "${KUSTOMIZE_DIR}/overlays/${env}" 2>/dev/null | grep "image:" | sort | uniq
        echo ""

        echo "ConfigMaps and Secrets:"
        echo "----------------------"
        kubectl kustomize "${KUSTOMIZE_DIR}/overlays/${env}" 2>/dev/null | yq eval-all '. | select(.kind == "ConfigMap" or .kind == "Secret") | .metadata.name' | sort | uniq
        echo ""

    } > "$report_file"

    log_info "Report saved to: $report_file"
}

# Main validation flow
main() {
    local env="${1:-production}"

    log_info "Starting Kustomize validation for environment: $env"

    # Check prerequisites
    check_prerequisites || exit 1

    # Run validations
    local total_errors=0

    validate_base || ((total_errors++))
    validate_overlays || ((total_errors+=$?))
    check_required_resources "$env" || ((total_errors+=$?))
    validate_networks "$env" || ((total_errors+=$?))
    check_resource_limits "$env"
    dry_run_apply "$env" || ((total_errors++))

    # Generate report
    generate_report "$env"

    # Summary
    echo ""
    if [[ $total_errors -eq 0 ]]; then
        log_info "✅ All validations passed!"
    else
        log_error "❌ Validation failed with $total_errors error(s)"
        exit 1
    fi
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [ENVIRONMENT]

Validate Kustomize configurations for RHOSO deployment

Arguments:
  ENVIRONMENT    Environment to validate (default: production)

Options:
  -h, --help     Show this help message
  -d, --diff     Show diff between two environments
  -a, --all      Validate all environments
  -r, --report   Generate detailed report only
  -v, --verbose  Enable verbose output

Examples:
  $0                          # Validate production
  $0 development              # Validate development
  $0 --diff dev prod          # Compare dev and prod
  $0 --all                    # Validate all environments

EOF
}

# Parse arguments
VALIDATE_ALL=false
SHOW_DIFF=false
REPORT_ONLY=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--diff)
            SHOW_DIFF=true
            shift
            ;;
        -a|--all)
            VALIDATE_ALL=true
            shift
            ;;
        -r|--report)
            REPORT_ONLY=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            set -x
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Execute based on options
if [[ "$SHOW_DIFF" == "true" ]]; then
    generate_diff "${1:-development}" "${2:-production}"
elif [[ "$VALIDATE_ALL" == "true" ]]; then
    for env in development staging production; do
        echo ""
        log_info "========== Validating $env =========="
        main "$env"
    done
elif [[ "$REPORT_ONLY" == "true" ]]; then
    generate_report "${1:-production}"
else
    main "${1:-production}"
fi