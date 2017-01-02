<#
    Invoke-Build script for DSC Configuration validation

    This script should be ubiquitious such that it can be run on a local workstation or within
    any build service and achieve the same outcome.

    Goals:
        - Verify the configuration module and configurations meet basic requirements using Pester
          and PSScriptAnalyzer.
        - Deploy the configurations and any required modules to Azure Automation using AzureRM
        - Verify the configurations compile successfully in Azure Automation using Pester
        - Deploy Azure VM instance(s) and apply configuration using AzureRM
        - Verify the server is configured as expected

    Test results should be clearly understood using reporting platforms that support NUnit XML.

    The process to validate any configuration should only require the author to clone this repo
    in to their project folder and execute 'Invoke-Build' from a PowerShell session, providing
    input parameters for Azure authentication, etc.
#>
param(
    $ApplicationID = (property ApplicationID),
    $ApplicationPassword = (property ApplicationPassword),
    $TenantID = (property TenantID)
)

# Synopsis: Baseline the environment
task Install {
    exec { try {
          Set-Location $env:APPVEYOR_BUILD_FOLDER

          # Load modules from test repo
          Import-Module -Name $env:APPVEYOR_BUILD_FOLDER\DscConfiguration.Tests\TestHelper.psm1 -Force
          
          # Install supporting environment modules from PSGallery
          $EnvironmentModules = @(
            'Pester',
            'PSScriptAnalyzer',
            'AzureRM'
          )
          Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.205 -Force | Out-Null
          Install-Module -Name $EnvironmentModules -Repository PSGallery -Force
          
          # Fix module path if duplicates exist (TestHelper)
          Invoke-UniquePSModulePath
          
          # Discover required modules from Configuration manifest (TestHelper)
          $Modules = Get-RequiredGalleryModules -ManifestData (Import-PowerShellDataFile -Path "$env:APPVEYOR_BUILD_FOLDER\$env:APPVEYOR_PROJECT_NAME.psd1") -Install
          Write-Host "Downloaded modules:`n$($Modules | Foreach -Process {$_.Name})"

          # Prep and import Configurations from module (TestHelper)
          Import-ModuleFromSource -Name $env:APPVEYOR_PROJECT_NAME
          $Configurations = Invoke-ConfigurationPrep -Module $env:APPVEYOR_PROJECT_NAME -Path "$env:TEMP\$env:APPVEYOR_PROJECT_ID"
          Write-Host "Prepared configurations:`n$($Configurations | Foreach -Process {$_.Name})"
        }
        catch [System.Exception] {
            throw $error
        }
    }

}

# Synopsis: Run Lint and Unit Tests
task UnitTests {
    Set-Location $env:APPVEYOR_BUILD_FOLDER
    $testResultsFile = "$env:APPVEYOR_BUILD_FOLDER\TestsResults.xml"
    $res = Invoke-Pester -OutputFormat NUnitXml -OutputFile $testResultsFile -PassThru
    (New-Object 'System.Net.WebClient').UploadFile("https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)", (Resolve-Path $testResultsFile))
    if ($res.FailedCount -gt 0) {
        throw "$($res.FailedCount) tests failed."
    }
}

# Synopsis: Perform Azure Login
task AzureLogin {
    # Login to Azure using information stored in AppVeyor
    Write-Host "Logging in to Azure"
    Invoke-AzureSPNLogin -ApplicationID $ApplicationID -ApplicationPassword $ApplicationPassword -TenantID $TenantID
}

# Synopsis: Deploys configuration and modules to Azure Automation
task AzureAutomation {
    try {
        # Create Azure Resource Group and Automation account (TestHelper)
        Write-Host "Creating Resource Group TestAutomation$env:APPVEYOR_BUILD_ID and Automation account DSCValidation$env:APPVEYOR_BUILD_ID"
        if (New-ResourceGroupForTests) {

            # Import the modules discovered as requirements to Azure Automation (TestHelper)
            Write-Host 'Importing modules to Azure Automation'
            foreach ($ImportModule in $Modules) {Import-ModuleToAzureAutomation -Module $ImportModule}
            
            # Allow module activities to extract before importing configuration (TestHelper)
            Write-Host 'Waiting for all modules to finish extracting activities'
            foreach ($WaitForModule in $Modules) {Wait-ModuleExtraction -Module $WaitForModule}
                
            # Import and compile the Configurations using Azure Automation (TestHelper)
            Write-Host 'Importing configurations to Azure Automation'              
            foreach ($ImportConfiguration in $Configurations) {Import-ConfigurationToAzureAutomation -Configuration $ImportConfiguration}

            # Wait for Configurations to compile
            Write-Host 'Waiting for configurations to finish compiling in Azure Automation'              
            foreach ($WaitForConfiguration in $Configurations) {Wait-ConfigurationCompilation -Configuration $WaitForConfiguration}
            }
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: remove all assets deployed to Azure and any local temporary changes (should be none)
task Clean {
    Remove-AzureTestResources
}

# Synopsis: default build tasks
task . Install, UnitTests, AzureLogin, AzureAutomation, Clean
