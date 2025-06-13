#!/bin/bash
# kustomize-workflow.sh - Master script for managing RHOSO Kustomize workflow

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUSTOMIZE_DIR="${SCRIPT_DIR}/kustomize"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging with emojis
log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step() { echo -e "${BLUE}▶${NC}  $1"; }
log_detail() { echo -e "  ${CYAN}↳${NC} $1"; }

# Banner
show_banner() {
    echo -e "${MAGENTA}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║       RHOSO Kustomize Workflow Manager v1.0               ║
║   Red Hat OpenStack Services on OpenShift Deployment      ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    local missing=()
    local tools=("kubectl" "kustomize" "yq" "oc" "ansible-playbook")

    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_detail "$tool: $(command -v $tool)"
        else
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        echo ""
        echo "Installation instructions:"
        echo "  kubectl:         https://kubernetes.io/docs/tasks/tools/"
        echo "  kustomize:       kubectl kustomize or https://kustomize.io/"
        echo "  yq:              pip install yq"
        echo "  oc:              https://mirror.openshift.com/pub/openshift-v4/clients/ocp/"
        echo "  ansible-playbook: pip install ansible"
        return 1
    fi

    log_info "All prerequisites satisfied"
}

# Setup Kustomize structure
setup_kustomize() {
    log_step "Setting up Kustomize structure..."

    if [[ -d "$KUSTOMIZE_DIR" ]]; then
        log_warn "Kustomize directory already exists"
        read -p "Overwrite existing structure? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
        rm -rf "$KUSTOMIZE_DIR"
    fi

    # Run setup script
    if [[ -f "${SCRIPT_DIR}/setup-kustomize.sh" ]]; then
        bash "${SCRIPT_DIR}/setup-kustomize.sh"
    else
        log_error "Setup script not found: setup-kustomize.sh"
        return 1
    fi

    log_info "Kustomize structure created"
}

# Generate from Ansible templates
generate_from_ansible() {
    log_step "Generating Kustomize files from Ansible templates..."

    if [[ ! -d "$ANSIBLE_DIR" ]]; then
        log_error "Ansible directory not found: $ANSIBLE_DIR"
        return 1
    fi

    # Check for config files
    if [[ ! -f "${ANSIBLE_DIR}/vars/network-config.yml" ]]; then
        log_error "Network configuration not found"
        log_detail "Create ${ANSIBLE_DIR}/vars/network-config.yml first"
        return 1
    fi

    # Run Ansible to generate files
    log_detail "Running Ansible playbook..."
    ansible-playbook \
        -i localhost, \
        "${ANSIBLE_DIR}/deploy-rhoso.yml" \
        -e "@${ANSIBLE_DIR}/vars/network-config.yml" \
        -e "@${ANSIBLE_DIR}/vars/deployment-config.yml" \
        -e "dry_run=true" \
        -e "generate_kustomize_only=true" \
        --tags generate-kustomize \
        || {
            log_error "Failed to generate from Ansible templates"
            return 1
        }

    log_info "Generated Kustomize files from templates"
}

# Validate Kustomize configuration
validate_kustomize() {
    local env="${1:-production}"

    log_step "Validating Kustomize configuration for $env..."

    if [[ -f "${SCRIPT_DIR}/validate-kustomize.sh" ]]; then
        bash "${SCRIPT_DIR}/validate-kustomize.sh" "$env"
    else
        # Basic validation
        if kubectl kustomize "${KUSTOMIZE_DIR}/overlays/${env}" > /dev/null 2>&1; then
            log_info "Kustomize build successful for $env"
        else
            log_error "Kustomize build failed for $env"
            kubectl kustomize "${KUSTOMIZE_DIR}/overlays/${env}" 2>&1 | tail -10
            return 1
        fi
    fi
}

# Interactive environment selection
select_environment() {
    local environments=("development" "staging" "production" "custom")

    echo ""
    echo "Select environment:"
    select env in "${environments[@]}"; do
        case $env in
            "development"|"staging"|"production")
                echo "$env"
                return 0
                ;;
            "custom")
                read -p "Enter custom environment name: " custom_env
                echo "$custom_env"
                return 0
                ;;
            *)
                log_error "Invalid selection"
                ;;
        esac
    done
}

# Build Kustomize for environment
build_kustomize() {
    local env="${1:-production}"
    local output_file="${2:-}"

    log_step "Building Kustomize for $env environment..."

    local overlay_dir="${KUSTOMIZE_DIR}/overlays/${env}"

    if [[ ! -d "$overlay_dir" ]]; then
        log_error "Environment overlay not found: $env"
        return 1
    fi

    if [[ -n "$output_file" ]]; then
        log_detail "Output file: $output_file"
        kubectl kustomize "$overlay_dir" > "$output_file"
    else
        kubectl kustomize "$overlay_dir"
    fi

    log_info "Build completed for $env"
}

# Deploy to cluster
deploy_to_cluster() {
    local env="${1:-production}"
    local dry_run="${2:-true}"

    log_step "Deploying to cluster (environment: $env, dry-run: $dry_run)..."

    # Check cluster access
    if ! oc whoami &> /dev/null; then
        log_error "Not logged into OpenShift cluster"
        log_detail "Run: oc login <cluster-url>"
        return 1
    fi

    local cluster_info=$(oc whoami --show-server)
    local current_user=$(oc whoami)

    log_detail "Cluster: $cluster_info"
    log_detail "User: $current_user"

    # Confirm deployment
    if [[ "$dry_run" != "true" ]]; then
        echo ""
        log_warn "⚠️  THIS WILL DEPLOY TO THE LIVE CLUSTER ⚠️"
        echo "Environment: $env"
        echo "Cluster: $cluster_info"
        read -p "Are you sure? (yes/NO) " -r
        if [[ ! $REPLY == "yes" ]]; then
            log_info "Deployment cancelled"
            return 0
        fi
    fi

    # Deploy
    local overlay_dir="${KUSTOMIZE_DIR}/overlays/${env}"

    if [[ "$dry_run" == "true" ]]; then
        log_detail "Running dry-run..."
        kubectl apply -k "$overlay_dir" --dry-run=client
    else
        log_detail "Deploying..."
        kubectl apply -k "$overlay_dir"
    fi

    log_info "Deployment completed"
}

# Show diff between environments
show_diff() {
    local env1="${1:-development}"
    local env2="${2:-production}"

    log_step "Showing diff between $env1 and $env2..."

    local temp_dir=$(mktemp -d)

    kubectl kustomize "${KUSTOMIZE_DIR}/overlays/${env1}" > "${temp_dir}/${env1}.yaml"
    kubectl kustomize "${KUSTOMIZE_DIR}/overlays/${env2}" > "${temp_dir}/${env2}.yaml"

    # Use diff with color if available
    if command -v colordiff &> /dev/null; then
        colordiff -u "${temp_dir}/${env1}.yaml" "${temp_dir}/${env2}.yaml" | less -R
    else
        diff -u "${temp_dir}/${env1}.yaml" "${temp_dir}/${env2}.yaml" | less
    fi

    rm -rf "$temp_dir"
}

# Create custom overlay
create_custom_overlay() {
    read -p "Enter overlay name: " overlay_name

    if [[ -z "$overlay_name" ]]; then
        log_error "Overlay name cannot be empty"
        return 1
    fi

    local overlay_dir="${KUSTOMIZE_DIR}/overlays/${overlay_name}"

    if [[ -d "$overlay_dir" ]]; then
        log_error "Overlay already exists: $overlay_name"
        return 1
    fi

    log_step "Creating custom overlay: $overlay_name"

    # Create directory structure
    mkdir -p "${overlay_dir}"/{patches,resources}

    # Select base environment to copy from
    echo "Select base environment to copy from:"
    select base_env in development staging production none; do
        case $base_env in
            "development"|"staging"|"production")
                cp -r "${KUSTOMIZE_DIR}/overlays/${base_env}"/* "${overlay_dir}/"
                log_detail "Copied from $base_env"
                break
                ;;
            "none")
                # Create minimal kustomization
                cat > "${overlay_dir}/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: openstack

bases:
  - ../../base

namePrefix: ${overlay_name}-

commonLabels:
  environment: ${overlay_name}

# Add your customizations here
patchesStrategicMerge: []
resources: []
EOF
                break
                ;;
        esac
    done

    log_info "Created custom overlay: $overlay_name"
    log_detail "Edit: ${overlay_dir}/kustomization.yaml"
}

# Interactive menu
show_menu() {
    while true; do
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo -e "${CYAN}    RHOSO Kustomize Workflow Menu      ${NC}"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        echo ""
        echo "1)  Setup Kustomize structure"
        echo "2)  Generate from Ansible templates"
        echo "3)  Validate configuration"
        echo "4)  Build for environment"
        echo "5)  Deploy to cluster (dry-run)"
        echo "6)  Deploy to cluster (apply)"
        echo "7)  Show diff between environments"
        echo "8)  Create custom overlay"
        echo "9)  Convert existing YAML to Kustomize"
        echo "10) Show current configuration"
        echo ""
        echo "q) Quit"
        echo ""
        read -p "Select option: " choice

        case $choice in
            1)
                setup_kustomize
                ;;
            2)
                generate_from_ansible
                ;;
            3)
                env=$(select_environment)
                validate_kustomize "$env"
                ;;
            4)
                env=$(select_environment)
                read -p "Output file (leave empty for stdout): " output
                build_kustomize "$env" "$output"
                ;;
            5)
                env=$(select_environment)
                deploy_to_cluster "$env" true
                ;;
            6)
                env=$(select_environment)
                deploy_to_cluster "$env" false
                ;;
            7)
                echo "Select first environment:"
                env1=$(select_environment)
                echo "Select second environment:"
                env2=$(select_environment)
                show_diff "$env1" "$env2"
                ;;
            8)
                create_custom_overlay
                ;;
            9)
                if [[ -f "${SCRIPT_DIR}/convert-to-kustomize.sh" ]]; then
                    read -p "Source directory/file: " source
                    bash "${SCRIPT_DIR}/convert-to-kustomize.sh" "$source"
                else
                    log_error "Conversion script not found"
                fi
                ;;
            10)
                show_configuration
                ;;
            q|Q)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
}

# Show current configuration
show_configuration() {
    log_step "Current Configuration"

    echo ""
    echo "Directories:"
    log_detail "Kustomize: $KUSTOMIZE_DIR"
    log_detail "Ansible: $ANSIBLE_DIR"

    if [[ -d "$KUSTOMIZE_DIR" ]]; then
        echo ""
        echo "Available overlays:"
        for overlay in "$KUSTOMIZE_DIR/overlays"/*; do
            if [[ -d "$overlay" ]]; then
                log_detail "$(basename "$overlay")"
            fi
        done
    fi

    if command -v oc &> /dev/null && oc whoami &> /dev/null 2>&1; then
        echo ""
        echo "OpenShift cluster:"
        log_detail "Server: $(oc whoami --show-server)"
        log_detail "User: $(oc whoami)"
        log_detail "Project: $(oc project -q)"
    fi
}

# Quick mode for CI/CD
quick_mode() {
    local action="$1"
    local env="${2:-production}"

    case $action in
        validate)
            validate_kustomize "$env"
            ;;
        build)
            build_kustomize "$env"
            ;;
        deploy)
            deploy_to_cluster "$env" false
            ;;
        deploy-dry-run)
            deploy_to_cluster "$env" true
            ;;
        *)
            log_error "Unknown action: $action"
            echo "Valid actions: validate, build, deploy, deploy-dry-run"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    show_banner

    # Check prerequisites first
    check_prerequisites || exit 1

    # Parse command line arguments
    if [[ $# -gt 0 ]]; then
        # Quick mode for automation
        quick_mode "$@"
    else
        # Interactive mode
        show_menu
    fi
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [ACTION] [ENVIRONMENT]

RHOSO Kustomize Workflow Manager

Actions (for automation):
  validate [ENV]        Validate Kustomize configuration
  build [ENV]          Build Kustomize manifests
  deploy [ENV]         Deploy to cluster
  deploy-dry-run [ENV] Deploy to cluster (dry-run)

Environment defaults to 'production' if not specified.

Interactive mode:
  $0                   Start interactive menu

Examples:
  $0                          # Interactive mode
  $0 validate development     # Validate dev environment
  $0 build production        # Build production manifests
  $0 deploy staging          # Deploy to staging

EOF
}

# Handle help
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Run main
main "$@"