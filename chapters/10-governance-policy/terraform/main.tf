# Chapter 10: policy as code at a test management group.
#
#   <parent> (tenant root group by default)
#   └── <prefix>-policytest
#         ├── custom definition   <prefix>-require-rg-tag       (from ../lib)
#         ├── custom initiative   <prefix>-guardrails           (custom + built-in)
#         ├── assignment          <prefix>-guardrails           (Audit, DoNotEnforce, non-compliance messages)
#         ├── exemption           <prefix>-loc-waiver           (Waiver, expires, allowed-locations only)
#         ├── assignment          <prefix>-inherit-tag          (built-in Modify + managed identity)
#         ├── role assignment     the identity's roles from the definition
#         └── remediation task    optional (create_remediation_task)

locals {
  mg_name = "${var.prefix}-policytest"

  # Built-in definition IDs, from Learn's built-in policy list:
  # https://learn.microsoft.com/azure/governance/policy/samples/built-in-policies
  builtin_allowed_locations = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c" # Allowed locations (General)
  builtin_inherit_tag_name  = "ea3f2387-9b95-492a-a190-fcdc54f7b070"                                                      # Inherit a tag from the resource group if missing (Tags)

  # The custom definition lives in a JSON file shared with the Bicep version.
  require_tag = jsondecode(file("${path.module}/../lib/require-rg-tag.policy.json")).properties

  exemption_expires_on = coalesce(var.exemption_expires_on, try(time_offset.exemption_expiry[0].rfc3339, null))
}

# ---------------------------------------------------------------------------
# The test management group
# ---------------------------------------------------------------------------

resource "azurerm_management_group" "test" {
  name                       = local.mg_name
  display_name               = "Policy test (${var.prefix})"
  parent_management_group_id = var.parent_management_group_id == null ? null : "/providers/Microsoft.Management/managementGroups/${var.parent_management_group_id}"
}

# ---------------------------------------------------------------------------
# 1. Custom policy definition, stored on the test management group
# ---------------------------------------------------------------------------

resource "azurerm_policy_definition" "require_rg_tag" {
  name                = "${var.prefix}-require-rg-tag"
  management_group_id = azurerm_management_group.test.id
  policy_type         = "Custom"
  mode                = local.require_tag.mode
  display_name        = local.require_tag.displayName
  description         = local.require_tag.description
  metadata            = jsonencode(local.require_tag.metadata)
  parameters          = jsonencode(local.require_tag.parameters)
  policy_rule         = jsonencode(local.require_tag.policyRule)
}

# ---------------------------------------------------------------------------
# 2. Custom initiative: the custom definition plus a built-in
# ---------------------------------------------------------------------------

resource "azurerm_management_group_policy_set_definition" "guardrails" {
  name                = "${var.prefix}-guardrails"
  management_group_id = azurerm_management_group.test.id
  policy_type         = "Custom"
  display_name        = "Guardrails: required tag and allowed locations (${var.prefix})"
  description         = "Chapter 10 example initiative: one custom definition and one built-in, sharing an effect parameter."
  metadata            = jsonencode({ category = "General", version = "1.0.0" })

  # Initiative parameters. Each member policy's parameters are wired to these
  # with "[parameters('...')]" expressions below.
  parameters = jsonencode({
    tagName = {
      type     = "String"
      metadata = { displayName = "Required tag name" }
    }
    effect = {
      type          = "String"
      defaultValue  = "Audit"
      allowedValues = ["Audit", "Deny", "Disabled"]
      metadata      = { displayName = "Effect for both policies" }
    }
    listOfAllowedLocations = {
      type     = "Array"
      metadata = { displayName = "Allowed locations", strongType = "location" }
    }
  })

  policy_definition_reference {
    reference_id         = "requireRgTag"
    policy_definition_id = azurerm_policy_definition.require_rg_tag.id
    parameter_values = jsonencode({
      tagName = { value = "[parameters('tagName')]" }
      effect  = { value = "[parameters('effect')]" }
    })
  }

  policy_definition_reference {
    reference_id         = "allowedLocations"
    policy_definition_id = local.builtin_allowed_locations
    parameter_values = jsonencode({
      listOfAllowedLocations = { value = "[parameters('listOfAllowedLocations')]" }
      effect                 = { value = "[parameters('effect')]" }
    })
  }
}

# ---------------------------------------------------------------------------
# 3. Assign the initiative, with non-compliance messages
# ---------------------------------------------------------------------------

resource "azurerm_management_group_policy_assignment" "guardrails" {
  name                 = "${var.prefix}-guardrails"
  display_name         = "Guardrails: required tag and allowed locations"
  description          = "Chapter 10 example. Reports (or with Deny and Default enforcement, blocks) untagged resource groups and resources outside the allowed regions."
  management_group_id  = azurerm_management_group.test.id
  policy_definition_id = azurerm_management_group_policy_set_definition.guardrails.id
  enforce              = var.enforcement_mode == "Default"

  parameters = jsonencode({
    tagName                = { value = var.required_tag_name }
    effect                 = { value = var.guardrail_effect }
    listOfAllowedLocations = { value = var.allowed_locations }
  })

  # The message without a reference ID is the default for the whole initiative;
  # the others replace it for one member policy.
  non_compliance_message {
    content = "This breaks the platform guardrails. See the landing zone guide or ask the platform team."
  }
  non_compliance_message {
    content                        = "Resource groups must have a '${var.required_tag_name}' tag. Add it and deploy again."
    policy_definition_reference_id = "requireRgTag"
  }
  non_compliance_message {
    content                        = "Only these regions are allowed: ${join(", ", var.allowed_locations)}. Ask the platform team for an exemption if you need another."
    policy_definition_reference_id = "allowedLocations"
  }
}

# ---------------------------------------------------------------------------
# 4. Exemption: a time-limited waiver from one member of the initiative
# ---------------------------------------------------------------------------

resource "time_offset" "exemption_expiry" {
  count       = var.exemption_expires_on == null ? 1 : 0
  offset_days = 30
}

resource "azurerm_management_group_policy_exemption" "location_waiver" {
  name                 = "${var.prefix}-loc-waiver"
  display_name         = "Waiver: allowed locations (test)"
  description          = "Temporary waiver from the allowed-locations rule only; the required-tag rule still applies."
  management_group_id  = azurerm_management_group.test.id
  policy_assignment_id = azurerm_management_group_policy_assignment.guardrails.id
  exemption_category   = "Waiver"
  expires_on           = local.exemption_expires_on

  # Only the allowed-locations member is exempt. Leave this out and the
  # exemption covers every policy in the initiative.
  policy_definition_reference_ids = ["allowedLocations"]

  metadata = jsonencode({
    requestedBy = "workload team (example)"
    approvedBy  = "platform team (example)"
    ticketRef   = "CHG-0000"
  })
}

# ---------------------------------------------------------------------------
# 5. Built-in Modify policy with a system-assigned managed identity
# ---------------------------------------------------------------------------

# Read the built-in definition so the role assignment uses whatever roles the
# definition itself lists in then.details.roleDefinitionIds.
data "azurerm_policy_definition_built_in" "inherit_tag" {
  name = local.builtin_inherit_tag_name
}

resource "azurerm_management_group_policy_assignment" "inherit_tag" {
  name                 = "${var.prefix}-inherit-tag"
  display_name         = "Inherit the ${var.required_tag_name} tag from the resource group if missing"
  management_group_id  = azurerm_management_group.test.id
  policy_definition_id = data.azurerm_policy_definition_built_in.inherit_tag.id
  enforce              = var.enforcement_mode == "Default"
  location             = var.location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    tagName = { value = var.required_tag_name }
  })

  non_compliance_message {
    content = "Resources should carry their resource group's '${var.required_tag_name}' tag. A remediation task adds it."
  }
}

# Outside the portal, Azure Policy doesn't grant the identity its roles:
# without this, Modify on create/update and remediation tasks fail.
resource "azurerm_role_assignment" "inherit_tag" {
  for_each = toset([for id in data.azurerm_policy_definition_built_in.inherit_tag.role_definition_ids : lower(basename(id))])

  scope = azurerm_management_group.test.id
  # Built-in role IDs in the form Azure returns them (no scope prefix): a
  # management-group-prefixed ID makes every plan replace this assignment.
  role_definition_id = "/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id       = azurerm_management_group_policy_assignment.inherit_tag.identity[0].principal_id
  principal_type     = "ServicePrincipal"
  description        = "Policy assignment ${azurerm_management_group_policy_assignment.inherit_tag.name}: roles from the definition's roleDefinitionIds"
}

# ---------------------------------------------------------------------------
# 6. Remediation task (optional)
# ---------------------------------------------------------------------------

resource "azurerm_management_group_policy_remediation" "inherit_tag" {
  count = var.create_remediation_task ? 1 : 0

  name                 = "${var.prefix}-inherit-tag-remediation"
  management_group_id  = azurerm_management_group.test.id
  policy_assignment_id = azurerm_management_group_policy_assignment.inherit_tag.id

  depends_on = [azurerm_role_assignment.inherit_tag]
}
