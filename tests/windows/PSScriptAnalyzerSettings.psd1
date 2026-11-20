# PSScriptAnalyzer settings for skills\ (used by Invoke-Lint.ps1).
@{
    Severity     = @('Error', 'Warning')
    # The pca-* scripts are interactive console tools; Write-Host is the intended output there.
    ExcludeRules = @('PSAvoidUsingWriteHost')
}
