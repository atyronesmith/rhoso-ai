#!/bin/bash
# convert-to-kustomize.sh - Convert existing YAML resources to Kustomize structure

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUSTOMIZE_DIR="${SCRIPT_DIR}/kustomize"
SOURCE_DIR="${1:-.}"
TEMP_DIR="${SCRIPT_DIR}/.convert-temp"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Resource categories
declare -A RESOURCE_CATEGORIES=(
    ["NetworkAttachmentDefinition"]="networking"
    ["NodeNetworkConfigurationPolicy"]="networking"
    ["IPAddressPool"]="networking"
    ["L2Advertisement"]="networking"
    ["NetConfig"]="networking"
    ["OpenStackControlPlane"]="controlplane"
    ["OpenStackDataPlaneNodeSet"]="dataplane"
    ["OpenStackDataPlaneDeployment"]="dataplane"
    ["BareMetalHost"]="dataplane"
    ["Secret"]="secrets"
    ["ConfigMap"]="configmaps"
)

# Initialize directories
init_directories() {
    log_info "Initializing Kustomize directory structure..."

    # Create base directories
    for category in networking controlplane dataplane secrets configmaps; do
        mkdir -p "${KUSTOMIZE_DIR}/base/${category}"
    done

    # Create overlay directories
    mkdir -p "${KUSTOMIZE_DIR}/overlays"/{development,staging,production}/{patches,resources}

    # Create temp directory
    mkdir -p "$TEMP_DIR"
}

# Split multi-document YAML
split_yaml_documents() {
    local input_file="$1"
    local output_dir="$2"

    log_info "Splitting YAML documents from: $input_file"

    # Use yq to split documents
    local doc_count=0
    yq eval-all -s '"'${output_dir}'/doc-" + $index + ".yaml"' "$input_file" 2>/dev/null || {
        # Fallback to awk if yq fails
        awk '
            /^---/ { if (doc_count > 0) close(outfile); doc_count++; outfile = sprintf("'${output_dir}'/doc-%d.yaml", doc_count); next }
            doc_count > 0 { print > outfile }
            END { if (doc_count > 0) close(outfile) }
        ' doc_count=0 "$input_file"
    }

    # Count documents
    local count=$(ls -1 "${output_dir}"/doc-*.yaml 2>/dev/null | wc -l)
    log_info "Split into $count documents"
}

# Categorize resource
categorize_resource() {
    local file="$1"

    # Extract kind
    local kind=$(yq eval '.kind' "$file" 2>/dev/null)

    if [[ -z "$kind" || "$kind" == "null" ]]; then
        echo "unknown"
        return
    fi

    # Check category mapping
    if [[ -n "${RESOURCE_CATEGORIES[$kind]:-}" ]]; then
        echo "${RESOURCE_CATEGORIES[$kind]}"
    else
        echo "unknown"
    fi
}

# Process single resource file
process_resource() {
    local file="$1"
    local base_dir="$2"

    # Get resource metadata
    local kind=$(yq eval '.kind' "$file" 2>/dev/null)
    local name=$(yq eval '.metadata.name' "$file" 2>/dev/null)
    local namespace=$(yq eval '.metadata.namespace' "$file" 2>/dev/null)

    if [[ -z "$kind" || "$kind" == "null" ]]; then
        log_warn "Skipping file without kind: $file"
        return
    fi

    # Categorize resource
    local category=$(categorize_resource "$file")

    if [[ "$category" == "unknown" ]]; then
        log_warn "Unknown resource type: $kind (will be placed in resources/)"
        category="resources"
        mkdir -p "${base_dir}/resources"
    fi

    # Generate filename
    local filename="${kind,,}-${name}.yaml"
    if [[ "$name" == "null" || -z "$name" ]]; then
        filename="${kind,,}-$(date +%s).yaml"
    fi

    # Copy to appropriate directory
    local target_dir="${base_dir}/${category}"
    local target_file="${target_dir}/${filename}"

    log_info "Processing $kind/$name -> ${category}/${filename}"

    # Process the resource
    {
        echo "# Source: $(basename "$file")"
        echo "# Converted: $(date)"
        if [[ -n "$namespace" && "$namespace" != "null" ]]; then
            echo "# Original namespace: $namespace"
        fi
        echo "---"
        # Remove namespace from metadata for base resources
        yq eval 'del(.metadata.namespace)' "$file"
    } > "$target_file"

    # Extract environment-specific values for patches
    extract_environment_values "$file" "$kind" "$name"
}

# Extract environment-specific values
extract_environment_values() {
    local file="$1"
    local kind="$2"
    local name="$3"

    # Skip if no name
    if [[ "$name" == "null" || -z "$name" ]]; then
        return
    fi

    # Create patch templates for common customizations
    case "$kind" in
        "OpenStackControlPlane")
            # Extract replica counts
            for env in development staging production; do
                local patch_dir="${KUSTOMIZE_DIR}/overlays/${env}/patches"
                local patch_file="${patch_dir}/controlplane-replicas.yaml"

                cat > "$patch_file" << EOF
apiVersion: core.openstack.org/v1beta1
kind: OpenStackControlPlane
metadata:
  name: $name
spec:
  # TODO: Adjust replica counts for $env environment
  # Example:
  # keystone:
  #   template:
  #     replicas: $([ "$env" == "production" ] && echo 3 || echo 1)
EOF
            done
            ;;

        "Secret")
            # Create placeholder for environment-specific secrets
            for env in development staging production; do
                local patch_dir="${KUSTOMIZE_DIR}/overlays/${env}/patches"
                local patch_file="${patch_dir}/secret-${name}-patch.yaml"

                if [[ ! -f "$patch_file" ]]; then
                    cat > "$patch_file" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: $name
stringData:
  # TODO: Add $env-specific values
  # environment: $env
EOF
                fi
            done
            ;;
    esac
}

# Generate kustomization files
generate_kustomization_files() {
    log_info "Generating kustomization.yaml files..."

    # Generate base kustomization files
    for category in networking controlplane dataplane secrets configmaps resources; do
        local dir="${KUSTOMIZE_DIR}/base/${category}"
        if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
            local files=($(ls -1 "$dir"/*.yaml 2>/dev/null | xargs -n1 basename))

            cat > "${dir}/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
$(printf '  - %s\n' "${files[@]}")

commonLabels:
  app.kubernetes.io/component: ${category}
  app.kubernetes.io/part-of: rhoso
EOF
        fi
    done

    # Generate main base kustomization
    cat > "${KUSTOMIZE_DIR}/base/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: openstack

resources:
EOF

    # Add resource directories that have content
    for category in networking controlplane dataplane secrets configmaps resources; do
        if [[ -d "${KUSTOMIZE_DIR}/base/${category}" ]] && [[ -n "$(ls -A "${KUSTOMIZE_DIR}/base/${category}" 2>/dev/null)" ]]; then
            echo "  - ${category}/" >> "${KUSTOMIZE_DIR}/base/kustomization.yaml"
        fi
    done

    # Add common metadata
    cat >> "${KUSTOMIZE_DIR}/base/kustomization.yaml" << 'EOF'

commonLabels:
  app.kubernetes.io/name: rhoso
  app.kubernetes.io/managed-by: kustomize

commonAnnotations:
  converted-by: convert-to-kustomize.sh
  conversion-date: '$(date -Iseconds)'
EOF

    # Generate overlay kustomization files
    for env in development staging production; do
        local overlay_dir="${KUSTOMIZE_DIR}/overlays/${env}"

        # Find patches
        local patches=($(find "${overlay_dir}/patches" -name "*.yaml" 2>/dev/null | xargs -n1 basename))

        cat > "${overlay_dir}/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: openstack

bases:
  - ../../base

namePrefix: ${env}-
nameSuffix: ""

commonLabels:
  environment: ${env}

commonAnnotations:
  deployment.rhoso.openstack.org/environment: ${env}
EOF

        # Add patches if any
        if [[ ${#patches[@]} -gt 0 ]]; then
            cat >> "${overlay_dir}/kustomization.yaml" << EOF

patchesStrategicMerge:
$(printf '  - patches/%s\n' "${patches[@]}")
EOF
        fi

        # Add environment-specific configuration
        cat >> "${overlay_dir}/kustomization.yaml" << EOF

# TODO: Add environment-specific customizations
# configMapGenerator:
#   - name: ${env}-config
#     literals:
#       - environment=${env}

# secretGenerator:
#   - name: ${env}-secrets
#     literals:
#       - password=changeme

# replicas:
#   - name: nova-api
#     count: $([ "$env" == "production" ] && echo 3 || echo 1)
EOF
    done
}

# Process directory of YAML files
process_directory() {
    local dir="$1"

    log_info "Processing directory: $dir"

    # Find all YAML files
    local yaml_files=($(find "$dir" -name "*.yaml" -o -name "*.yml" 2>/dev/null))

    if [[ ${#yaml_files[@]} -eq 0 ]]; then
        log_warn "No YAML files found in $dir"
        return
    fi

    log_info "Found ${#yaml_files[@]} YAML files"

    # Process each file
    for yaml_file in "${yaml_files[@]}"; do
        log_info "Processing file: $yaml_file"

        # Create temp directory for this file
        local file_temp="${TEMP_DIR}/$(basename "$yaml_file")"
        mkdir -p "$file_temp"

        # Split multi-document YAML
        split_yaml_documents "$yaml_file" "$file_temp"

        # Process each document
        for doc in "$file_temp"/doc-*.yaml; do
            if [[ -f "$doc" ]]; then
                process_resource "$doc" "${KUSTOMIZE_DIR}/base"
            fi
        done

        # Cleanup
        rm -rf "$file_temp"
    done
}

# Generate conversion report
generate_report() {
    local report_file="${SCRIPT_DIR}/kustomize-conversion-report.txt"

    log_info "Generating conversion report..."

    {
        echo "Kustomize Conversion Report"
        echo "=========================="
        echo "Generated: $(date)"
        echo "Source: $SOURCE_DIR"
        echo ""

        echo "Converted Resources:"
        echo "-------------------"
        for category in networking controlplane dataplane secrets configmaps resources; do
            local dir="${KUSTOMIZE_DIR}/base/${category}"
            if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
                echo ""
                echo "${category}:"
                ls -1 "$dir"/*.yaml 2>/dev/null | while read file; do
                    local kind=$(yq eval '.kind' "$file" 2>/dev/null)
                    local name=$(yq eval '.metadata.name' "$file" 2>/dev/null)
                    echo "  - $kind/$name"
                done
            fi
        done

        echo ""
        echo "Directory Structure:"
        echo "-------------------"
        tree -d "$KUSTOMIZE_DIR" 2>/dev/null || find "$KUSTOMIZE_DIR" -type d | sort

        echo ""
        echo "Next Steps:"
        echo "-----------"
        echo "1. Review generated files in: $KUSTOMIZE_DIR"
        echo "2. Update environment-specific patches in overlays/"
        echo "3. Test with: kubectl kustomize $KUSTOMIZE_DIR/overlays/production"
        echo "4. Apply with: kubectl apply -k $KUSTOMIZE_DIR/overlays/production"

    } > "$report_file"

    log_info "Report saved to: $report_file"
}

# Main conversion process
main() {
    log_info "Starting conversion to Kustomize structure"
    log_info "Source directory: $SOURCE_DIR"
    log_info "Target directory: $KUSTOMIZE_DIR"

    # Initialize directories
    init_directories

    # Process source directory
    if [[ -d "$SOURCE_DIR" ]]; then
        process_directory "$SOURCE_DIR"
    elif [[ -f "$SOURCE_DIR" ]]; then
        # Single file
        local file_temp="${TEMP_DIR}/single"
        mkdir -p "$file_temp"
        split_yaml_documents "$SOURCE_DIR" "$file_temp"
        for doc in "$file_temp"/doc-*.yaml; do
            if [[ -f "$doc" ]]; then
                process_resource "$doc" "${KUSTOMIZE_DIR}/base"
            fi
        done
    else
        log_error "Source not found: $SOURCE_DIR"
        exit 1
    fi

    # Generate kustomization files
    generate_kustomization_files

    # Generate report
    generate_report

    # Cleanup
    rm -rf "$TEMP_DIR"

    log_info "✅ Conversion completed successfully!"
    log_info "Kustomize structure created in: $KUSTOMIZE_DIR"
    echo ""
    cat "${SCRIPT_DIR}/kustomize-conversion-report.txt"
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [SOURCE] [OPTIONS]

Convert existing YAML resources to Kustomize structure

Arguments:
  SOURCE         Directory or file containing YAML resources (default: current directory)

Options:
  -h, --help     Show this help message
  -o, --output   Output directory for Kustomize structure (default: ./kustomize)
  -f, --force    Overwrite existing Kustomize directory

Examples:
  $0                                    # Convert current directory
  $0 /path/to/yaml/files               # Convert specific directory
  $0 deployment.yaml                    # Convert single file
  $0 -o /tmp/kustomize deployment/     # Convert to specific output

EOF
}

# Parse arguments
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -o|--output)
            KUSTOMIZE_DIR="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        *)
            SOURCE_DIR="$1"
            shift
            ;;
    esac
done

# Check if output directory exists
if [[ -d "$KUSTOMIZE_DIR" ]] && [[ "$FORCE" != "true" ]]; then
    log_error "Output directory already exists: $KUSTOMIZE_DIR"
    log_error "Use -f/--force to overwrite"
    exit 1
fi

# Check for required tools
if ! command -v yq &> /dev/null; then
    log_error "yq is required but not installed"
    log_error "Install with: pip install yq"
    exit 1
fi

# Run main conversion
main