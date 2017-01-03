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
    $TenantID = (property TenantID),
    $BuildFolder = (property BuildFolder),
    $ProjectName = (property ProjectName),
    $ProjectID = (property ProjectID),
    $BuildID = (property BuildID)
)

# Synopsis: Baseline the environment
task Install {
    try {
        Set-Location $BuildFolder

        # Load modules from test repo
        Import-Module -Name $BuildFolder\DscConfiguration.Tests\TestHelper.psm1 -Force
        
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
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Load the Configuration modules and required resources
task Load {
    try {
        Set-Location $BuildFolder

        # Discover required modules from Configuration manifest (TestHelper)
        $Global:Modules = Get-RequiredGalleryModules -ManifestData (Import-PowerShellDataFile -Path "$BuildFolder\$ProjectName.psd1") -Install
        Write-Host "Downloaded modules:`n$($Modules | Foreach -Process {$_.Name})"

        # Prep and import Configurations from module (TestHelper)
        Import-ModuleFromSource -Name $ProjectName
        $Global:Configurations = Invoke-ConfigurationPrep -Module $ProjectName -Path "$env:TEMP\$ProjectID"
        Write-Host "Prepared configurations:`n$($Configurations | Foreach -Process {$_.Name})"
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Run Lint and Unit Tests
task UnitTests {
    Set-Location $BuildFolder
    $testResultsFile = "$BuildFolder\TestsResults.xml"
    $res = Invoke-Pester -OutputFormat NUnitXml -OutputFile $testResultsFile -PassThru
    #TODO Test if results should go to AppVeyor
    (New-Object 'System.Net.WebClient').UploadFile("https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)", (Resolve-Path $testResultsFile))
    if ($res.FailedCount -gt 0) {
        throw "$($res.FailedCount) tests failed."
    }
}

# Synopsis: Perform Azure Login
task AzureLogin {
    # Login to Azure using information from params
    Write-Host "Logging in to Azure"
    Invoke-AzureSPNLogin -ApplicationID $ApplicationID -ApplicationPassword $ApplicationPassword -TenantID $TenantID
}

# Synopsis: Deploys configuration and modules to Azure Automation
#TODO modules and configurations are empty when this section is run; build script output section to input section?
task AzureAutomation {
    try {
        # Create Azure Resource Group and Automation account (TestHelper)
        Write-Host "Creating Resource Group TestAutomation$BuildID and Automation account DSCValidation$BuildID"
        if (New-ResourceGroupForTests) {

            # Import the modules discovered as requirements to Azure Automation (TestHelper)
            Write-Host 'Importing modules to Azure Automation'
            foreach ($ImportModule in $Global:Modules) {Import-ModuleToAzureAutomation -Module $ImportModule}
            
            # Allow module activities to extract before importing configuration (TestHelper)
            Write-Host 'Waiting for all modules to finish extracting activities'
            foreach ($WaitForModule in $Global:Modules) {Wait-ModuleExtraction -Module $WaitForModule}
                
            # Import and compile the Configurations using Azure Automation (TestHelper)
            Write-Host 'Importing configurations to Azure Automation'              
            foreach ($ImportConfiguration in $Global:Configurations) {Import-ConfigurationToAzureAutomation -Configuration $ImportConfiguration}

            # Wait for Configurations to compile
            Write-Host 'Waiting for configurations to finish compiling in Azure Automation'              
            foreach ($WaitForConfiguration in $Global:Configurations) {Wait-ConfigurationCompilation -Configuration $WaitForConfiguration}
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
task . Install, Load, UnitTests, AzureLogin, AzureAutomation, Clean
