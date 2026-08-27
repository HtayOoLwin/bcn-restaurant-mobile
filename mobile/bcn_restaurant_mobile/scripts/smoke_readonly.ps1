param(
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][SecureString]$Password,
    [string]$BaseUrl = "https://bcndemo-restaurant.nvi.frappe.cloud"
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd('/')
$plainPassword = [System.Net.NetworkCredential]::new('', $Password).Password

function Invoke-FrappeGetMethod {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [hashtable]$Query = @{}
    )

    $uri = "$BaseUrl/api/method/$Method"
    if ($Query.Count -gt 0) {
        $parts = foreach ($entry in $Query.GetEnumerator()) {
            "$([Uri]::EscapeDataString([string]$entry.Key))=$([Uri]::EscapeDataString([string]$entry.Value))"
        }
        $uri = "$uri?$($parts -join '&')"
    }

    $getParams = @{
        Uri        = $uri
        Method     = "Get"
        WebSession = $FrappeSession
    }
    return Invoke-RestMethod @getParams
}

try {
    $loginParams = @{
        Uri             = "$BaseUrl/api/method/login"
        Method          = "Post"
        Body            = @{ usr = $User; pwd = $plainPassword }
        ContentType     = "application/x-www-form-urlencoded"
        SessionVariable = "FrappeSession"
    }
    Invoke-RestMethod @loginParams | Out-Null

    $bootstrapResponse = Invoke-FrappeGetMethod -Method "bcn_mobile_bootstrap"
    $bootstrap = $bootstrapResponse.message

    Write-Host "Authenticated as: $($bootstrap.user)" -ForegroundColor Green
    Write-Host "Roles: $($bootstrap.roles -join ', ')"
    Write-Host "Company: $($bootstrap.company)"

    if ($bootstrap.permissions.waiter) {
        $tablesResponse = Invoke-FrappeGetMethod -Method "bcn_mobile_tables" -Query @{ service_type = "dine_in" }
        $menuResponse = Invoke-FrappeGetMethod -Method "bcn_mobile_menu"
        Write-Host "Waiter smoke: $($tablesResponse.message.tables.Count) dine-in tables, $($menuResponse.message.items.Count) menu items" -ForegroundColor Green

        $progressResponse = Invoke-FrappeGetMethod -Method "bcn_waiter_order_progress"
        $readyResponse = Invoke-FrappeGetMethod -Method "bcn_waiter_orders"
        Write-Host "Waiter progress: $($progressResponse.message.count) active order(s), $($readyResponse.message.item_count) ready item(s)" -ForegroundColor Green
    }

    if ($bootstrap.permissions.kitchen -and $bootstrap.kitchen_counters.Count -gt 0) {
        $kitchenResponse = Invoke-FrappeGetMethod -Method "bcn_kitchen_orders"
        Write-Host "Kitchen smoke: $($kitchenResponse.message.item_count) active preparation item(s)" -ForegroundColor Green
    }

    Write-Host "Read-only smoke test completed. No orders or statuses were changed." -ForegroundColor Green
} finally {
    $plainPassword = $null
}
