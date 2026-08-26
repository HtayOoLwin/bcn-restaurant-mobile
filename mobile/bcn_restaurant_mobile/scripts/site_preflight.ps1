param(
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][SecureString]$Password,
    [string]$BaseUrl = "https://bcndemo-restaurant.nvi.frappe.cloud"
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

    $requiredDoctypes = @("Restaurant Settings", "Restaurant Table Session")
    foreach ($doctype in $requiredDoctypes) {
        $encoded = [Uri]::EscapeDataString($doctype)
        $getParams = @{
            Uri        = "$BaseUrl/api/resource/DocType/$encoded"
            Method     = "Get"
            WebSession = $FrappeSession
        }
        Invoke-RestMethod @getParams | Out-Null
        Write-Host "OK: $doctype exists" -ForegroundColor Green
    }

    $bootstrapParams = @{
        Uri        = "$BaseUrl/api/method/bcn_restaurant.api.bootstrap.get_bootstrap"
        Method     = "Get"
        WebSession = $FrappeSession
    }
    $bootstrap = Invoke-RestMethod @bootstrapParams

    Write-Host "OK: bcn_restaurant mobile API is installed" -ForegroundColor Green
    Write-Host "Company: $($bootstrap.message.company)"
    Write-Host "Price List: $($bootstrap.message.selling_price_list)"
} finally {
    $plainPassword = $null
}
