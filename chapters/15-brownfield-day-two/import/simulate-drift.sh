#!/usr/bin/env bash
# Chapter 15: make two "portal changes" to the adopted resources, so the drift
# checks have something to find:
#   1. an extra NSG rule (RDP from anywhere: the classic emergency change)
#   2. a changed tag on the VNet
# Both are free. Run the drift workflow (or terraform plan / what-if) afterwards,
# then put things back with terraform apply, or with --undo.
#
# Usage: bash simulate-drift.sh <subscription-id> [prefix] [location] [--undo]

set -euo pipefail

SUB="${1:?usage: simulate-drift.sh <subscription-id> [prefix] [location] [--undo]}"
PREFIX="${2:-alz}"
LOCATION="${3:-uksouth}"
UNDO="${4:-}"

NAME="${PREFIX}-brownfield-${LOCATION}"
RG="rg-${NAME}"

if [ "$UNDO" = "--undo" ]; then
  az network nsg rule delete --subscription "$SUB" -g "$RG" --nsg-name "nsg-${NAME}" --name emergency-rdp
  az network vnet update --subscription "$SUB" -g "$RG" --name "vnet-${NAME}" --set tags.environment=test --output none
  echo "Drift removed."
  exit 0
fi

az network nsg rule create --subscription "$SUB" -g "$RG" --nsg-name "nsg-${NAME}" \
  --name emergency-rdp --priority 300 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes '*' --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges 3389 --output none

az network vnet update --subscription "$SUB" -g "$RG" --name "vnet-${NAME}" \
  --set tags.environment=production --output none

echo "Drift introduced: NSG rule emergency-rdp and VNet tag environment=production."
