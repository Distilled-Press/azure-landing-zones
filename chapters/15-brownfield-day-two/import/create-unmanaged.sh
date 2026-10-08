#!/usr/bin/env bash
# Chapter 15: simulate a brownfield estate.
#
# Creates a resource group, an NSG with one rule and a VNet with one subnet
# that uses the NSG, with the Azure CLI only: no Terraform state, no Bicep
# deployment, nothing that records them as managed. This is what "someone built
# it in the portal" looks like. All three resources are free.
#
# Usage: bash create-unmanaged.sh <subscription-id> [prefix] [location]

set -euo pipefail

SUB="${1:?usage: create-unmanaged.sh <subscription-id> [prefix] [location]}"
PREFIX="${2:-alz}"
LOCATION="${3:-uksouth}"

NAME="${PREFIX}-brownfield-${LOCATION}"
RG="rg-${NAME}"
NSG="nsg-${NAME}"
VNET="vnet-${NAME}"
SUBNET="snet-app"

echo "Creating ${RG}, ${NSG} and ${VNET} in subscription ${SUB}"

az group create --subscription "$SUB" --name "$RG" --location "$LOCATION" \
  --tags environment=test owner=app-team --output none

az network nsg create --subscription "$SUB" --resource-group "$RG" --name "$NSG" \
  --location "$LOCATION" --tags environment=test --output none

# One inbound rule: HTTPS from inside the VNet.
az network nsg rule create --subscription "$SUB" --resource-group "$RG" --nsg-name "$NSG" \
  --name allow-https-from-vnet --priority 200 --direction Inbound --access Allow \
  --protocol Tcp --source-address-prefixes VirtualNetwork --source-port-ranges '*' \
  --destination-address-prefixes VirtualNetwork --destination-port-ranges 443 --output none

az network vnet create --subscription "$SUB" --resource-group "$RG" --name "$VNET" \
  --location "$LOCATION" --address-prefixes 10.20.0.0/24 --tags environment=test --output none

# The subnet is set explicitly to no default outbound access, so the IaC
# versions can state the same value and plan/what-if show no difference.
az network vnet subnet create --subscription "$SUB" --resource-group "$RG" --vnet-name "$VNET" \
  --name "$SUBNET" --address-prefixes 10.20.0.0/26 --network-security-group "$NSG" \
  --default-outbound false --output none

echo "Done. Resource IDs:"
az resource list --subscription "$SUB" --resource-group "$RG" --query "[].id" --output tsv
az group show --subscription "$SUB" --name "$RG" --query id --output tsv
