# Load pw2401.ps1 to load all dependencies
$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
. (Join-Path $ProjectRoot "pw2401.ps1")

$resourcePath = Join-Path $ProjectRoot "tests\resources\SampleConfig.json"
Write-LogMessage "Testing with resource: $resourcePath" -Level Info

$config = Get-Content $resourcePath | ConvertFrom-Json
if ($config.test_name -eq "pw2401-test") {
    Write-LogMessage "Test Passed: Successfully read test resource." -Level Success
} else {
    Write-LogMessage "Test Failed: Resource parsing incorrect." -Level Error
}
