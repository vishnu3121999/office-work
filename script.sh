#!/bin/bash

# Usage: ./convert_config_to_json.sh config.yaml dev

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <config.yaml> <environment>"
    exit 1
fi

CONFIG_FILE=$1
ENVIRONMENT=$2

# Check if yq and jq are installed
if ! command -v yq &> /dev/null || ! command -v jq &> /dev/null; then
    echo "Please install yq and jq to run this script."
    exit 1
fi

# Initialize the deployment JSON structure
DEPLOYMENT_JSON='{}'

# Extract `helm_chart_version` from the YAML file
HELM_CHART_VERSION=$(yq '.helm_chart_version' "$CONFIG_FILE")

# Loop through each cluster in the config.yaml
yq '.deploy' "$CONFIG_FILE" -o json | jq -c 'to_entries[]' | while read -r CLUSTER_ENTRY; do
    CLUSTER_NAME=$(echo "$CLUSTER_ENTRY" | jq -r '.key')
    NAMESPACES=$(echo "$CLUSTER_ENTRY" | jq -r '.value | to_entries[]')

    INCLUDE_ARRAY="[]"

    # Loop through each namespace and activity in the cluster
    echo "$NAMESPACES" | while read -r NAMESPACE_ENTRY; do
        NAMESPACE=$(echo "$NAMESPACE_ENTRY" | jq -r '.key')
        ACTIVITIES=$(echo "$NAMESPACE_ENTRY" | jq -r '.value[]')

        for ACTIVITY in $ACTIVITIES; do
            ACTIVITY_NAME=$(basename "$ACTIVITY")

            # Create a JSON object for the activity
            INCLUDE_OBJECT=$(jq -n \
                --arg helm_chart_name "camera-app-helm-charts" \
                --arg helm_chart_version "$HELM_CHART_VERSION" \
                --arg helm_chart_dir "hlm-public-local/com/db/cashmgmt/$HELM_CHART_VERSION" \
                --arg helm_values_file_name "values.yaml -f $ACTIVITY/values.yaml -f $ACTIVITY/$ENVIRONMENT/values-$NAMESPACE.yaml" \
                --arg gke_namespace "$NAMESPACE" \
                '{
                    helm_chart_name: $helm_chart_name,
                    helm_chart_version: $helm_chart_version,
                    helm_chart_dir: $helm_chart_dir,
                    helm_values_file_name: $helm_values_file_name,
                    gke_namespace: $gke_namespace
                }')

            # Add the object to the include array
            INCLUDE_ARRAY=$(echo "$INCLUDE_ARRAY" | jq ". + [$INCLUDE_OBJECT]")
        done
    done

    # Add the cluster entry to the deployment JSON
    DEPLOYMENT_JSON=$(echo "$DEPLOYMENT_JSON" | jq \
        --arg cluster "$CLUSTER_NAME" \
        --argjson include "$INCLUDE_ARRAY" \
        '. + {($cluster): {include: $include}}')
done

# Save the JSON to deployment.json
echo "$DEPLOYMENT_JSON" | jq '.' > deployment.json

echo "Generated deployment.json successfully."
