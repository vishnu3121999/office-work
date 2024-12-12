#!/bin/bash

# Input files
CLUSTER_REGION_FILE="clusterRegion.json"
CONFIG_FILE="config.yaml"
OUTPUT_FILE="install.json"

# Static list for workloads that should use "values.yaml" without appending cluster name
STATIC_VALUES_LIST=("w2" "w3")

# Temporary files for parsing
TMP_CLUSTER="/tmp/clusters.tmp"
TMP_INSTALL="/tmp/install.tmp"

# Function to check if a workload is in the static list
is_in_static_list() {
    local workload=$1
    for item in "${STATIC_VALUES_LIST[@]}"; do
        if [[ "$item" == "$workload" ]]; then
            return 0 # True
        fi
    done
    return 1 # False
}

# Extract clusters and regions from clusterRegion.json
jq -r '.[] | .cluster.name + " " + .cluster.region' "$CLUSTER_REGION_FILE" > "$TMP_CLUSTER"

# Extract helm install configurations from config.yaml
yq eval '.mongo.install[] | .name + " " + .version' "$CONFIG_FILE" > "$TMP_INSTALL"

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
echo "Generated $OUTPUT_FILE successfully."
