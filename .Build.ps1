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
    $env:BuildFolder = (property BuildFolder),
    $ProjectName = (property ProjectName),
    $ProjectID = (property ProjectID),
    $BuildID = (property BuildID)
)

function Write-Task {
param(
    [string]$Name,
    [switch]$End
)
    if ($End) {
        Write-Output ''
        Write-Output "########## End of Task $Name ##########"
        Write-Output ''
    }
    else {
        Write-Output ''
        Write-Output "########## Start of Task $Name ##########"
        Write-Output ''
    }    
}

# Synopsis: Baseline the environment
task Install {
    try {
        Write-Task Install
        Set-Location $env:BuildFolder

        # Load modules from test repo
        Import-Module -Name $env:BuildFolder\DscConfiguration.Tests\TestHelper.psm1 -Force
        
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
        Write-Task Install -End
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Load the Configuration modules and required resources
task Load {
    try {
        Write-Task Load
        Set-Location $env:BuildFolder

        # Discover required modules from Configuration manifest (TestHelper)
        $script:Modules = Get-RequiredGalleryModules -ManifestData (Import-PowerShellDataFile `
        -Path "$env:BuildFolder\$ProjectName.psd1") -Install
        Write-Output "Downloaded modules:`n$($Modules | Foreach -Process {$_.Name})"

        # Prep and import Configurations from module (TestHelper)
        Import-ModuleFromSource -Name $ProjectName
        $script:Configurations = Invoke-ConfigurationPrep -Module $ProjectName -Path `
        "$env:TEMP\$ProjectID"
        Write-Output "Prepared configurations:`n$($Configurations | Foreach -Process {$_.Name})"
        Write-Task Load -End
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Run Lint and Unit Tests
task LintUnitTests {
    try {
        Write-Task LintUnitTests
        Set-Location $env:BuildFolder

        $testResultsFile = "$env:BuildFolder\TestsResults.xml"

        $res = Invoke-Pester -Tag Lint,Unit -OutputFormat NUnitXml -OutputFile $testResultsFile `
        -PassThru
        
        #TODO Test if results should go to AppVeyor
        (New-Object 'System.Net.WebClient').UploadFile( `
        "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)", `
        (Resolve-Path $testResultsFile))
        
        if ($res.FailedCount -gt 0) {
            throw "$($res.FailedCount) tests failed."
        }
    }
    catch [System.Exception] {
        throw $error
    }
    Write-Task LintUnitTests -End
}

# Synopsis: Perform Azure Login
task AzureLogin {
    try {
        Write-Task AzureLogin
        # Login to Azure using information from params
        Write-Output "Logging in to Azure"
        Invoke-AzureSPNLogin -ApplicationID $ApplicationID -ApplicationPassword `
        $ApplicationPassword -TenantID $TenantID
        Write-Task AzureLogin -End
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Create Resource Group
task ResourceGroupAndAutomationAccount {
    try {
        Write-Task ResourceGroupAndAutomationAccount
        # Create Azure Resource Group and Automation account (TestHelper)
        Write-Output "Creating Resource Group TestAutomation$BuildID"
        Write-Output "and Automation account DSCValidation$BuildID"
        New-ResourceGroupandAutomationAccount
        Write-Task ResourceGroupAndAutomationAccount -End
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Deploys modules to Azure Automation
task AzureAutomationModules {
    try {
        Write-Task AzureAutomationModules
        Set-Location $env:BuildFolder

        # Import the modules discovered as requirements to Azure Automation (TestHelper)
        foreach ($ImportModule in $script:Modules) {
            Write-Output "Importing module $($ImportModule.Name) to Azure Automation"
            Import-ModuleToAzureAutomation -Module $ImportModule
        }
        
        # Allow module activities to extract before importing configuration (TestHelper)
        Write-Output 'Waiting for all modules to finish extracting activities'
        foreach ($WaitForModule in $script:Modules) {Wait-ModuleExtraction -Module $WaitForModule}
        Write-Task AzureAutomationModules -End
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Deploys configurations to Azure Automation
task AzureAutomationConfigurations {
    try {
        Write-Task AzureAutomationConfigurations
        Set-Location $env:BuildFolder

        # Import and compile the Configurations using Azure Automation (TestHelper)
        foreach ($ImportConfiguration in $script:Configurations) {
            Write-Output "Importing configuration $($ImportConfiguration.Name) to Azure Automation"
            Import-ConfigurationToAzureAutomation -Configuration $ImportConfiguration
        }

        # Wait for Configurations to compile
        Write-Output 'Waiting for configurations to finish compiling in Azure Automation'              
        foreach ($WaitForConfiguration in $script:Configurations) {
            Wait-ConfigurationCompilation -Configuration $WaitForConfiguration
        }
        Write-Task AzureAutomationConfigurations -End
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Deploys Azure VM and bootstraps to Azure Automation DSC
task AzureVM {
    try {
        Write-Task AzureVM
        foreach ($testConfiguration in $script:Configurations) {
            # Retrieve Azure Automation DSC registration information
            $Account = Get-AzureRMAutomationAccount -ResourceGroupName "TestAutomation$BuildID" `
            -Name "DSCValidation$BuildID"
            $RegistrationInfo = $Account | Get-AzureRmAutomationRegistrationInfo
            $registrationUrl = $RegistrationInfo.Endpoint
            $registrationKey = $RegistrationInfo.PrimaryKey | ConvertTo-SecureString -AsPlainText `
            -Force
            
            # Random password for local administrative account
            $adminPassword = new-randompassword -length 24 -UseSpecialCharacters | `
            ConvertTo-SecureString -AsPlainText -Force

            # DNS name based on random chars followed by first 10 of configuration name
            $dnsLabelPrefix = "$(Get-Random -Minimum 1000 -Maximum 9999) `
            $($testConfiguration.Name.substring(0,10))"

            New-AzureRMResourceGroupDeployment -Name $BuildID -ResourceGroupName "TestAutomation$BuildID" -TemplateFile "$BuildFolder\DSCConfiguration.Tests\AzureDeploy.json" -TemplateParameterFile "$BuildFolder\DSCConfiguration.Tests\AzureDeploy.parameters.json" -dnsLabelPrefix $dnsLabelPrefix -vmName $testConfiguration -adminPassword $adminPassword -registrationUrl $registrationUrl -registrationKey $registrationKey -nodeConfigurationName $testConfiguration.localhost -verbose
        }
        Write-Task AzureVM -End
    }
    catch [System.Exception] {
        throw $error
    }    
}

# Synopsis: remove all assets deployed to Azure and any local temporary changes (should be none)
task Clean {
    Write-Task Clean
    Remove-AzureTestResources
    Write-Task Clean -End
}

# Synopsis: default build tasks
task . Install, Load, LintUnitTests, AzureLogin, ResourceGroupAndAutomationAccount, `
AzureAutomationModules, AzureAutomationConfigurations, AzureVM, Clean
