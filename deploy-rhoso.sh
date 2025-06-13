#!/bin/bash
# deploy-rhoso.sh - Wrapper script for RHOSO deployment

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
VARS_DIR="${ANSIBLE_DIR}/vars"
TEMPLATES_DIR="${ANSIBLE_DIR}/templates"
TASKS_DIR="${ANSIBLE_DIR}/tasks"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check for required commands
    local required_cmds=("oc" "ansible-playbook" "kubectl" "jq")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "$cmd is not installed"
            exit 1
        fi
    done

    # Check OpenShift login
    if ! oc whoami &> /dev/null; then
        print_error "Not logged into OpenShift. Please run 'oc login' first"
        exit 1
    fi

    # Check for cluster-admin privileges
    if ! oc auth can-i '*' '*' --all-namespaces &> /dev/null; then
        print_warn "You may not have cluster-admin privileges. Some operations might fail."
    fi

    print_info "Prerequisites check passed"
}

setup_directory_structure() {
    print_info "Setting up directory structure..."

    mkdir -p "${VARS_DIR}"
    mkdir -p "${TEMPLATES_DIR}"
    mkdir -p "${TASKS_DIR}"
    mkdir -p "${SCRIPT_DIR}/kustomize"
    mkdir -p "${SCRIPT_DIR}/backups"
    mkdir -p "${SCRIPT_DIR}/logs"
}

validate_configuration() {
    print_info "Validating configuration files..."

    # Check if configuration files exist
    if [[ ! -f "${VARS_DIR}/network-config.yml" ]]; then
        print_error "Network configuration file not found: ${VARS_DIR}/network-config.yml"
        exit 1
    fi

    if [[ ! -f "${VARS_DIR}/deployment-config.yml" ]]; then
        print_error "Deployment configuration file not found: ${VARS_DIR}/deployment-config.yml"
        exit 1
    fi

    # Validate YAML syntax
    if ! ansible-playbook --syntax-check "${ANSIBLE_DIR}/deploy-rhoso.yml" &> /dev/null; then
        print_error "Ansible playbook syntax check failed"
        exit 1
    fi

    print_info "Configuration validation passed"
}

backup_existing_resources() {
    print_info "Backing up existing resources..."

    local backup_dir="${SCRIPT_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    # Backup existing RHOSO resources if they exist
    local resources=("openstackcontrolplane" "openstackdataplanenodeset" "openstackdataplanedeployment")
    for resource in "${resources[@]}"; do
        if oc get "$resource" -n openstack &> /dev/null; then
            print_info "Backing up $resource resources"
            oc get "$resource" -n openstack -o yaml > "$backup_dir/${resource}.yaml"
        fi
    done

    print_info "Backup completed in $backup_dir"
}

deploy_rhoso() {
    print_info "Starting RHOSO deployment..."

    local log_file="${SCRIPT_DIR}/logs/deployment_$(date +%Y%m%d_%H%M%S).log"

    # Run the Ansible playbook
    ansible-playbook \
        -i localhost, \
        "${ANSIBLE_DIR}/deploy-rhoso.yml" \
        -e "@${VARS_DIR}/network-config.yml" \
        -e "@${VARS_DIR}/deployment-config.yml" \
        2>&1 | tee "$log_file"

    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        print_info "Deployment completed successfully"
        print_info "Log file: $log_file"
    else
        print_error "Deployment failed. Check log file: $log_file"
        exit 1
    fi
}

post_deployment_checks() {
    print_info "Running post-deployment checks..."

    # Check control plane status
    print_info "Checking control plane status..."
    if oc get openstackcontrolplane -n openstack -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
        print_info "Control plane is ready"
    else
        print_warn "Control plane is not ready yet"
    fi

    # Check data plane status
    print_info "Checking data plane status..."
    if oc get openstackdataplanenodeset -n openstack -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then
        print_info "Data plane is ready"
    else
        print_warn "Data plane is not ready yet"
    fi

    # Show access information
    print_info "Access information:"
    echo "OpenStack Client: oc rsh -n openstack openstackclient"
    echo "Monitor deployment: watch 'oc get openstackcontrolplane,openstackdataplanenodeset,openstackdataplanedeployment -n openstack'"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Red Hat OpenStack Services on OpenShift (RHOSO)

OPTIONS:
    -h, --help              Show this help message
    -c, --check-only        Run prerequisite checks only
    -d, --dry-run           Generate configurations without applying them
    -b, --backup            Backup existing resources before deployment
    -s, --skip-checks       Skip prerequisite checks
    -e, --environment NAME  Specify environment name (default: production)
    -v, --verbose           Enable verbose output

EXAMPLES:
    # Run a dry-run deployment
    $0 --dry-run

    # Deploy with backup
    $0 --backup

    # Deploy specific environment
    $0 --environment staging

    # Check prerequisites only
    $0 --check-only

EOF
}

# Parse command line arguments
DRY_RUN=false
BACKUP=false
CHECK_ONLY=false
SKIP_CHECKS=false
ENVIRONMENT="production"
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -c|--check-only)
            CHECK_ONLY=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -b|--backup)
            BACKUP=true
            shift
            ;;
        -s|--skip-checks)
            SKIP_CHECKS=true
            shift
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_info "RHOSO Deployment Script"
    print_info "Environment: ${ENVIRONMENT}"

    if [[ "$CHECK_ONLY" == "true" ]]; then
        check_prerequisites
        validate_configuration
        print_info "All checks passed"
        exit 0
    fi

    if [[ "$SKIP_CHECKS" != "true" ]]; then
        check_prerequisites
    fi

    setup_directory_structure
    validate_configuration

    if [[ "$BACKUP" == "true" ]]; then
        backup_existing_resources
    fi

    # Set additional Ansible variables
    export ANSIBLE_VARS=""
    if [[ "$DRY_RUN" == "true" ]]; then
        ANSIBLE_VARS="${ANSIBLE_VARS} -e dry_run=true"
        print_info "Running in DRY-RUN mode - no resources will be created"
    fi

    if [[ "$VERBOSE" == "true" ]]; then
        ANSIBLE_VARS="${ANSIBLE_VARS} -vvv"
    fi

    ANSIBLE_VARS="${ANSIBLE_VARS} -e environment_name=${ENVIRONMENT}"

    # Deploy RHOSO
    deploy_rhoso

    if [[ "$DRY_RUN" != "true" ]]; then
        post_deployment_checks
    fi

    print_info "Deployment script completed"
}

# Run main function
main
