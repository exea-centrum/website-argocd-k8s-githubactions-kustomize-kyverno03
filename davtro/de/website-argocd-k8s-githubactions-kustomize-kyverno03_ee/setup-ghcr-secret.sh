#!/bin/bash

set -e

echo "🔐 Konfiguracja GHCR pull secret..."

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "❌ Użycie: ./setup-ghcr-secret.sh <GITHUB_USERNAME> <GITHUB_TOKEN>"
    echo "   Token musi mieć uprawnienie: read:packages"
    exit 1
fi

GITHUB_USERNAME=$1
GITHUB_TOKEN=$2
NAMESPACE="davtro"

# Tworzenie dockerconfigjson
DOCKER_CONFIG_JSON=$(cat << END
{
  "auths": {
    "ghcr.io": {
      "auth": "$(echo -n "$GITHUB_USERNAME:$GITHUB_TOKEN" | base64 -w 0)"
    }
  }
}
END
)

# Kodowanie base64
ENCODED_CONFIG=$(echo "$DOCKER_CONFIG_JSON" | base64 -w 0)

# Aktualizacja secret
kubectl patch secret ghcr-pull-secret -n $NAMESPACE --type='json' -p="[{\"op\": \"replace\", \"path\": \"/data/.dockerconfigjson\", \"value\": \"$ENCODED_CONFIG\"}]"

echo "✅ GHCR secret zaktualizowany pomyślnie!"
echo "🔍 Sprawdź secret: kubectl get secret ghcr-pull-secret -n $NAMESPACE -o yaml"
