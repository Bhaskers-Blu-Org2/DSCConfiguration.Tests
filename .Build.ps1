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

<##>
function Write-Task {
    param(
        [string]$Name
    )
    Write-Output `n
    Write-Build -Color Cyan -Text "########## $Name ##########"
}

Enter-BuildTask {
    $BuildRoot = $BuildFolder
    Write-task $task.Name
}
Exit-BuildTask {
    # PLACEHOLDER
}

# Synopsis: Baseline the environment
Enter-Build {
    Write-Output "The build folder is $BuildFolder"
    # Load modules from test repo
    Import-Module -Name $BuildFolder\DscConfiguration.Tests\TestHelper.psm1 -Force
    
    # Install supporting environment modules from PSGallery
    $EnvironmentModules = @(
    'Pester',
    'PSScriptAnalyzer',
    'AzureRM'
    )
    $Nuget = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.205 -Force
    Write-Output "Installing modules to support the build environment:`n$EnvironmentModules"
    Install-Module -Name $EnvironmentModules -Repository PSGallery -Force
    
    # Fix module path if duplicates exist (TestHelper)
    Invoke-UniquePSModulePath
}

# Synopsis: Load the Configuration modules and required resources
task LoadModules {
    # Discover required modules from Configuration manifest (TestHelper)
    $script:Modules = Get-RequiredGalleryModules -ManifestData (Import-PowerShellDataFile `
    -Path "$BuildFolder\$ProjectName.psd1") -Install
    Write-Output "Loaded modules:`n$($script:Modules | ForEach-Object -Process {$_.Name})"

    # Prep and import Configurations from module (TestHelper)
    Import-ModuleFromSource -Name $ProjectName
    $script:Configurations = Invoke-ConfigurationPrep -Module $ProjectName -Path `
    "$env:TEMP\$ProjectID"
    Write-Output "Loaded configurations:`n$($script:Configurations | ForEach-Object -Process {$_.Name})"
}

# Synopsis: Run Lint and Unit Tests
task LintUnitTests {
    $testResultsFile = "$BuildFolder\LintUnitTestsResults.xml"

    $Pester = Invoke-Pester -Tag Lint,Unit -OutputFormat NUnitXml -OutputFile $testResultsFile `
    -PassThru
    
    (New-Object 'System.Net.WebClient').UploadFile("$env:TestResultsUploadURI", `
    (Resolve-Path $testResultsFile))
}

# Synopsis: Perform Azure Login
task AzureLogin {
    # Login to Azure using information from params
    Invoke-AzureSPNLogin -ApplicationID $ApplicationID -ApplicationPassword `
    $ApplicationPassword -TenantID $TenantID
}

# Synopsis: Create Resource Group
task ResourceGroupAndAutomationAccount {
    # Create Azure Resource Group and Automation account (TestHelper)
    New-ResourceGroupandAutomationAccount
}

# Synopsis: Deploys modules to Azure Automation
task AzureAutomationModules {
    # Import the modules discovered as requirements to Azure Automation (TestHelper)
    foreach ($ImportModule in $script:Modules) {
        Import-ModuleToAzureAutomation -Module $ImportModule
    }
    
    # Allow module activities to extract before importing configuration (TestHelper)
    Write-Output 'Waiting for all modules to finish extracting activities'
    foreach ($WaitForModule in $script:Modules) {Wait-ModuleExtraction -Module $WaitForModule}
}

# Synopsis: Deploys configurations to Azure Automation
task AzureAutomationConfigurations {
    # Import and compile the Configurations using Azure Automation (TestHelper)
    foreach ($ImportConfiguration in $script:Configurations) {
        Import-ConfigurationToAzureAutomation -Configuration $ImportConfiguration
    }

    # Wait for Configurations to compile
    Write-Output 'Waiting for configurations to finish compiling in Azure Automation'              
    foreach ($WaitForConfiguration in $script:Configurations) {
        Wait-ConfigurationCompilation -Configuration $WaitForConfiguration
    }
}

# Synopsis: Integration tests to verify that modules and configurations loaded to Azure Automation DSC successfully
task IntegrationTestAzureAutomationDSC {
    $testResultsFile = "$BuildFolder\AADSCIntegrationTestsResults.xml"

    $Pester = Invoke-Pester -Tag AADSCIntegration -OutputFormat NUnitXml `
    -OutputFile $testResultsFile -PassThru
    
    (New-Object 'System.Net.WebClient').UploadFile("$env:TestResultsUploadURI", `
    (Resolve-Path $testResultsFile))
}

# Synopsis: Deploys Azure VM and bootstraps to Azure Automation DSC
task AzureVM {
    $VMDeployments = @()
    Write-Output 'Deploying all test virtual machines in parallel'
    ForEach ($Configuration in $script:Configurations) {
      ForEach ($WindowsOSVersion in $Configuration.WindowsOSVersion) {
        Write-Output "Deploying $WindowsOSVersion and bootstrapping configuration $($Configuration.Name)"
        $JobName = "$($Configuration.Name).$($WindowsOSVersion.replace('-',''))"
        $VMDeployment = Start-Job -ScriptBlock {
            param
            (
                [string]$BuildID,
                [string]$Configuration,
                [string]$WindowsOSVersion
            )
            Import-Module -Name $env:BuildFolder\DscConfiguration.Tests\TestHelper.psm1 -Force
            Invoke-AzureSPNLogin -ApplicationID $env:ApplicationID -ApplicationPassword `
            $env:ApplicationPassword -TenantID $env:TenantID
            New-AzureTestVM -BuildID $BuildID -Configuration $Configuration -WindowsOSVersion $WindowsOSVersion
        } -ArgumentList @($BuildID,$Configuration.Name,$WindowsOSVersion) -Name $JobName
        $VMDeployments += $VMDeployment
      }
    }
    # Wait for all VM deployments to finish (asynch)
    ForEach ($Job in $VMDeployments) {
        $Wait = Wait-Job -Job $Job
        Write-Output `n
        Write-Output "########## Output from $($Job.Name) ##########"
        Receive-Job -Job $Job
    }
}

# Synopsis: Integration tests to verify that DSC configuration successfuly applied in virtual machines
task IntegrationTestAzureVMs {
    $testResultsFile = "$BuildFolder\VMIntegrationTestsResults.xml"

    $Pester = Invoke-Pester -Tag AzureVMIntegration -OutputFormat NUnitXml -OutputFile $testResultsFile `
    -PassThru
    
    (New-Object 'System.Net.WebClient').UploadFile("$env:TestResultsUploadURI", `
    (Resolve-Path $testResultsFile))
}

# Synopsis: remove all assets deployed to Azure and any local temporary changes (should be none)
Exit-Build {
    Remove-AzureTestResources
}

# Synopsis: default build tasks
task . LoadModules, LintUnitTests, AzureLogin, ResourceGroupAndAutomationAccount, `
AzureAutomationModules, AzureAutomationConfigurations, IntegrationTestAzureAutomationDSC, `
AzureVM, IntegrationTestAzureVMs
