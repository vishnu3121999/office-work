#!/bin/bash

# Check for required tools
if ! command -v yq &> /dev/null || ! command -v jq &> /dev/null; then
    echo "Please install 'yq' and 'jq' to run this script."
    exit 1
fi

# Input arguments
ENV=$1
if [ -z "$ENV" ]; then
    echo "Usage: $0 <environment>"
    exit 1
fi

# Input and output files
YAML_FILE="config.yaml"
OUTPUT_JSON="deployment.json"

# Read helm_chart_version
HELM_VERSION=$(yq '.helm_chart_version' $YAML_FILE)

# Initialize the JSON object
JSON_OUTPUT="{}"

# Parse clusters and namespaces
CLUSTERS=$(yq '.deploy | keys' $YAML_FILE -o=json | jq -r '.[]')

for CLUSTER in $CLUSTERS; do
    # Initialize includes array
    INCLUDES=()

    # Parse namespaces and activities
    NAMESPACES=$(yq ".deploy.$CLUSTER | keys" $YAML_FILE -o=json | jq -r '.[]')
    for NAMESPACE in $NAMESPACES; do
        # Parse the activities array
        ACTIVITIES=$(yq ".deploy.$CLUSTER.$NAMESPACE" $YAML_FILE -o=json | jq -r '.[]')

        for ACTIVITY in $ACTIVITIES; do
            # Build include JSON object
            INCLUDE=$(jq -n \
                --arg helm_chart_name "camera-app-helm-charts" \
                --arg helm_chart_version "$HELM_VERSION" \
                --arg helm_chart_dir "hlm-public-local/com/db/cashmgmt/$HELM_VERSION" \
                --arg helm_values_file_name "values.yaml -f $ACTIVITY/values.yaml -f $ACTIVITY/$ENV/values-$NAMESPACE.yaml" \
                --arg gke_namespace "$NAMESPACE" \
                '{
                    helm_chart_name: $helm_chart_name,
                    helm_chart_version: $helm_chart_version,
                    helm_chart_dir: $helm_chart_dir,
                    helm_values_file_name: $helm_values_file_name,
                    gke_namespace: $gke_namespace
                }')
            INCLUDES+=("$INCLUDE")
        done
    done

    # Add cluster data to JSON output
    CLUSTER_JSON=$(jq -n --argjson includes "$(printf '%s\n' "${INCLUDES[@]}" | jq -s '.')" '{include: $includes}')
    JSON_OUTPUT=$(jq --arg cluster "$CLUSTER" --argjson clusterJson "$CLUSTER_JSON" '.[$cluster] = $clusterJson' <<< "$JSON_OUTPUT")
done

# Write to output JSON
echo "$JSON_OUTPUT" | jq . > "$OUTPUT_JSON"

echo "JSON conversion complete. Output written to $OUTPUT_JSON"
