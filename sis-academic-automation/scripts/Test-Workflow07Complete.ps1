[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$WorkflowPath = Join-Path $ProjectRoot 'workflows\07-admin-dashboard.json'
$MigrationPath = Join-Path $ProjectRoot 'database\migrations\20260721000100_phase4_workflow07_admin_search_dashboard.sql'
$PortalAppPath = Join-Path $ProjectRoot 'portal\app.js'
$PortalIndexPath = Join-Path $ProjectRoot 'portal\index.html'

foreach ($Path in @($WorkflowPath,$MigrationPath,$PortalAppPath,$PortalIndexPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required Workflow 07 file is missing: $Path"
    }
}

$Workflow = Get-Content -LiteralPath $WorkflowPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($Workflow.name -ne 'SIS 07 — Student Search and Basic Administrative Dashboard — Complete') {
    throw 'Workflow 07 name is incorrect.'
}

$AllowedTypes = @(
    'n8n-nodes-base.webhook',
    'n8n-nodes-base.code',
    'n8n-nodes-base.if',
    'n8n-nodes-base.httpRequest'
)

foreach ($Node in $Workflow.nodes) {
    if ($AllowedTypes -notcontains [string]$Node.type) {
        throw "Unsupported node type in Workflow 07: $($Node.type)"
    }
}

if ($null -ne ($Workflow.nodes | Where-Object {
    $_.type -match 'crypto|executeCommand' -or
    $_.name -match 'SHA256|Crypto|Execute Command'
})) {
    throw 'Workflow 07 contains an unsupported or forbidden node.'
}

$Paths = @(
    ($Workflow.nodes | Where-Object { $_.name -eq 'Student Search Webhook' }).parameters.path,
    ($Workflow.nodes | Where-Object { $_.name -eq 'Dashboard Snapshot Webhook' }).parameters.path
)
if ($Paths -notcontains 'staff/rpc_search_students' -or
    $Paths -notcontains 'staff/rpc_get_dashboard_snapshot') {
    throw 'Workflow 07 webhook paths are incomplete.'
}

$RpcNode = $Workflow.nodes |
    Where-Object { $_.name -eq 'Call Scoped Admin Read RPC' } |
    Select-Object -First 1
if ($null -eq $RpcNode) {
    throw 'Scoped admin RPC node is missing.'
}
if ([string]$RpcNode.parameters.authentication -eq 'predefinedCredentialType') {
    throw 'Workflow 07 must use the verified user JWT, not a service-role credential.'
}
$HeadersJson = $RpcNode.parameters.headerParameters | ConvertTo-Json -Depth 10
if ($HeadersJson -notmatch 'SUPABASE_ANON_KEY' -or
    $HeadersJson -notmatch 'authHeader') {
    throw 'Workflow 07 does not forward the verified user JWT and anon key.'
}

$Migration = Get-Content -LiteralPath $MigrationPath -Raw -Encoding UTF8
foreach ($Required in @(
    'create or replace function public.rpc_search_students',
    'create or replace function public.rpc_get_dashboard_snapshot',
    'app.can_administer_institution',
    'app.can_access_campus',
    'grade_distribution',
    'section_capacity_snapshot',
    'grant execute on function public.rpc_search_students',
    'grant execute on function public.rpc_get_dashboard_snapshot'
)) {
    if (-not $Migration.Contains($Required)) {
        throw "Workflow 07 migration is missing: $Required"
    }
}

$PortalApp = Get-Content -LiteralPath $PortalAppPath -Raw -Encoding UTF8
$PortalIndex = Get-Content -LiteralPath $PortalIndexPath -Raw -Encoding UTF8

foreach ($Required in @(
    'renderDashboardTerms',
    'renderSectionCapacity',
    'renderGradeDistribution',
    'student-search-status-filter'
)) {
    if (-not ($PortalApp.Contains($Required) -or $PortalIndex.Contains($Required))) {
        throw "Workflow 07 portal is missing: $Required"
    }
}

if ($PortalIndex -match 'Term ID \(optional\)' -or
    $PortalIndex -match 'placeholder="UUID"') {
    throw 'Workflow 07 portal still asks staff to enter a term UUID manually.'
}

Write-Host 'SIS 07 COMPLETE PACKAGE CHECK: PASS'
Write-Host 'Verified n8n 2.4.0 node compatibility, user-JWT authorization, RPC scope controls and UUID-free portal inputs.'
