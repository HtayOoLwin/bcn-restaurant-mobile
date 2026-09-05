param(
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][SecureString]$Password,
    [string]$BaseUrl = "https://ourcity.s.frappe.cloud"
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd('/')
$plainPassword = [System.Net.NetworkCredential]::new('', $Password).Password

try {
    $loginParams = @{
        Uri             = "$BaseUrl/api/method/login"
        Method          = "Post"
        Body            = @{ usr = $User; pwd = $plainPassword }
        ContentType     = "application/x-www-form-urlencoded"
        SessionVariable = "FrappeSession"
    }
    Invoke-RestMethod @loginParams | Out-Null

    $bootstrapParams = @{
        Uri        = "$BaseUrl/api/method/bcn_mobile_bootstrap"
        Method     = "Get"
        WebSession = $FrappeSession
    }
    $bootstrap = Invoke-RestMethod @bootstrapParams

    Write-Host "OK: Server Script mobile API is available" -ForegroundColor Green
    Write-Host "User: $($bootstrap.message.user)"
    Write-Host "Company: $($bootstrap.message.company)"
    Write-Host "Price List: $($bootstrap.message.selling_price_list)"
    Write-Host "Waiter: $($bootstrap.message.permissions.waiter)"
    Write-Host "Cashier: $($bootstrap.message.permissions.cashier)"
    Write-Host "Print Status: $($bootstrap.message.permissions.can_view_print_status)"
} finally {
    $plainPassword = $null
}
