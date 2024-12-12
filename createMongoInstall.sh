#!/bin/bash

# Input files
CLUSTER_REGION_FILE="clusterRegion.json"
CONFIG_FILE="config.yaml"

# Get input parameters
if [ $# -ne 2 ]; then
    echo "Usage: $0 <environment> <operation_type>"
    echo "Example: $0 dev install"
    exit 1
fi

ENVIRONMENT=$1
OPERATION_TYPE=$2
OUTPUT_FILE="mongo-${OPERATION_TYPE}.json"
# Static list for workloads that use "values.yaml" only
STATIC_VALUES_LIST=("w2" "w3")

# Static list for workloads requiring "values.yaml -f ./<name>/values-<env>.yaml"
STATIC_MULTI_VALUES_LIST=("w4")

# Temporary files for parsing
TMP_CLUSTER="/tmp/clusters.tmp"
TMP_INSTALL="/tmp/install.tmp"

# Function to check if a workload is in the static list for "values.yaml"
is_in_static_list() {
    local workload=$1
    for item in "${STATIC_VALUES_LIST[@]}"; do
        if [[ "$item" == "$workload" ]]; then
            return 0 # True
        fi
    done
    return 1 # False
}

# Function to check if a workload requires multiple values files
is_in_multi_values_list() {
    local workload=$1
    for item in "${STATIC_MULTI_VALUES_LIST[@]}"; do
        if [[ "$item" == "$workload" ]]; then
            return 0 # True
        fi
    done
    return 1 # False
}

# Extract clusters and regions from clusterRegion.json
jq -r '.[] | .cluster.name + " " + .cluster.region' "$CLUSTER_REGION_FILE" > "$TMP_CLUSTER"

# Extract helm install configurations from config.yaml
yq eval '.mongo.${OPERATION_TYPE}[] | .name + " " + .version' "$CONFIG_FILE" > "$TMP_INSTALL"

# Start building the JSON
{
    echo "["
    first_entry=true

    # Loop through each cluster
    while read -r cluster region; do
        # For each cluster, reset the helm install file reading
        while read -r helm_name helm_version; do

            # Decide on helm_values_file_name
            if is_in_static_list "$helm_name"; then
                values_file="values.yaml"
            elif is_in_multi_values_list "$helm_name"; then
                values_file="values.yaml -f ./${helm_name}/values-${ENVIRONMENT}.yaml"
            else
                values_file="values-${cluster}.yaml"
            fi

            # Helm chart directory
            helm_dir="hlm-public-local/com/db/cashmgmt/mongodb-charts/${helm_name}/${helm_version}"

            # Append JSON entry
            if [ "$first_entry" = true ]; then
                first_entry=false
            else
                echo ","
            fi

            cat <<EOF
        {
            "cluster": "$cluster",
            "region": "$region",
            "helm_chart_name": "$helm_name",
            "helm_chart_version": "$helm_version",
            "helm_chart_dir": "$helm_dir",
            "helm_values_file_name": "$values_file",
            "gke_namespace": "mongo"
        }
EOF

        done < "$TMP_INSTALL"
    done < "$TMP_CLUSTER"

    echo "]"
} > "$OUTPUT_FILE"

# Cleanup
rm -f "$TMP_CLUSTER" "$TMP_INSTALL"

# Output result
echo "Generated $OUTPUT_FILE successfully for environment: $ENVIRONMENT."
