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

<##>
function Write-Task {
param(
    [string]$Name
)
    Write-Output `n
    Write-Build -Color Cyan -Text "########## $Name ##########"
    Write-Output `n
}

Enter-BuildTask {
    Write-task $task.Name
}
Exit-BuildTask {
    # PLACEHOLDER
}

# Synopsis: Baseline the environment
Enter-Build {
try {
    Set-Location $env:BuildFolder

    # Load modules from test repo
    Import-Module -Name $env:BuildFolder\DscConfiguration.Tests\TestHelper.psm1 -Force
    $InvokeParallelFolder = (New-Item -ItemType Directory -Path "$env:ProgramFiles\WindowsPowerShell\Modules\InvokeParallel" -Force).FullName
    Invoke-WebRequest -Uri 'https://github.com/RamblingCookieMonster/Invoke-Parallel/raw/master/Invoke-Parallel/Invoke-Parallel.ps1' -OutFile "$InvokeParallelFolder\Invoke-Parallel.ps1"
    . "$InvokeParallelFolder\Invoke-Parallel.ps1"
    
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
task LoadModules {
    try {
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
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Run Lint and Unit Tests
task LintUnitTests {
    try {
        Set-Location $env:BuildFolder
        $testResultsFile = "$env:BuildFolder\LintUnitTestsResults.xml"

        $res = Invoke-Pester -Tag Lint,Unit -OutputFormat NUnitXml -OutputFile $testResultsFile `
        -PassThru
        
        #TODO Test if results should go to AppVeyor
        (New-Object 'System.Net.WebClient').UploadFile( `
        "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)", `
        (Resolve-Path $testResultsFile))
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Perform Azure Login
task AzureLogin {
    try {
        # Login to Azure using information from params
        Write-Output "Logging in to Azure"
        Invoke-AzureSPNLogin -ApplicationID $ApplicationID -ApplicationPassword `
        $ApplicationPassword -TenantID $TenantID
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Create Resource Group
task ResourceGroupAndAutomationAccount {
    try {
        # Create Azure Resource Group and Automation account (TestHelper)
        Write-Output "Creating Resource Group TestAutomation$BuildID"
        Write-Output "and Automation account DSCValidation$BuildID"
        New-ResourceGroupandAutomationAccount
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Deploys modules to Azure Automation
task AzureAutomationModules {
    try {
        Set-Location $env:BuildFolder

        # Import the modules discovered as requirements to Azure Automation (TestHelper)
        foreach ($ImportModule in $script:Modules) {
            Write-Output "Importing module $($ImportModule.Name) to Azure Automation"
            Import-ModuleToAzureAutomation -Module $ImportModule
        }
        
        # Allow module activities to extract before importing configuration (TestHelper)
        Write-Output 'Waiting for all modules to finish extracting activities'
        foreach ($WaitForModule in $script:Modules) {Wait-ModuleExtraction -Module $WaitForModule}
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Deploys configurations to Azure Automation
task AzureAutomationConfigurations {
    try {
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
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Integration tests to verify that modules and configurations loaded to Azure Automation DSC successfully
task IntegrationTestAzureAutomationDSC {
    try {
        Set-Location $env:BuildFolder
        $testResultsFile = "$env:BuildFolder\AADSCIntegrationTestsResults.xml"

        $res = Invoke-Pester -Tag AADSCIntegration -OutputFormat NUnitXml -OutputFile $testResultsFile `
        -PassThru
        
        #TODO Test if results should go to AppVeyor
        (New-Object 'System.Net.WebClient').UploadFile( `
        "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)", `
        (Resolve-Path $testResultsFile))
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: Deploys Azure VM and bootstraps to Azure Automation DSC
task AzureVM {
    try {
        $script:Configurations | Invoke-Parallel -ImportVariable -Scriptblock {
            Import-Module AzureRM -Force
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
            $dnsLabelPrefix = "$($testConfiguration.Name.substring(0,10).ToLower())$(Get-Random -Minimum 1000 -Maximum 9999)"

            New-AzureRMResourceGroupDeployment -Name $BuildID `
            -ResourceGroupName "TestAutomation$BuildID" `
            -TemplateFile "$env:BuildFolder\DSCConfiguration.Tests\AzureDeploy.json" `
            -TemplateParameterFile "$env:BuildFolder\DSCConfiguration.Tests\AzureDeploy.parameters.json" `
            -dnsLabelPrefix $dnsLabelPrefix 
            -vmName $testConfiguration `
            -adminPassword $adminPassword `
            -registrationUrl $registrationUrl `
            -registrationKey $registrationKey `
            -nodeConfigurationName "$($testConfiguration.Name).localhost"

            $Status = Get-AzureRMResourceGroupDeployment -ResourceGroupName "TestAutomation$BuildID" `
            -Name $BuildID

            if ($Status.ProvisioningState -eq 'Succeeded') {
                Write-Output $Status.Outputs
            }
            else {
                $Error = Get-AzureRMDeploymentOperation -ResourceGroupName "TestAutomation$BuildID" `
                -Name $BuildID
                $Message = $Error.Properties | Where-Object {$_.ProvisioningState -eq 'Failed'} | `
                ForEach-Object {$_.StatusMessage} | ForEach-Object {$_.Error} | `
                ForEach-Object {$_.Details} | ForEach-Object {$_.Message}
                Write-Error $Message
            }
        }
    }
    catch [System.Exception] {
        throw $error
    }    
}

# Synopsis: Integration tests to verify that DSC configuration successfuly applied in virtual machines
task IntegrationTestAzureVMs {
    try {
        Set-Location $env:BuildFolder
        $testResultsFile = "$env:BuildFolder\VMIntegrationTestsResults.xml"

        $res = Invoke-Pester -Tag VMIntegration -OutputFormat NUnitXml -OutputFile $testResultsFile `
        -PassThru
        
        #TODO Test if results should go to AppVeyor
        (New-Object 'System.Net.WebClient').UploadFile( `
        "https://ci.appveyor.com/api/testresults/nunit/$($env:APPVEYOR_JOB_ID)", `
        (Resolve-Path $testResultsFile))
    }
    catch [System.Exception] {
        throw $error
    }
}

# Synopsis: remove all assets deployed to Azure and any local temporary changes (should be none)
task Clean {
    Remove-AzureTestResources
}

Exit-Build {
        task Clean
}

# Synopsis: default build tasks
task . LoadModules, LintUnitTests, AzureLogin, ResourceGroupAndAutomationAccount, `
AzureAutomationModules, AzureAutomationConfigurations, IntegrationTestAzureAutomationDSC, `
AzureVM, IntegrationTestAzureVMs
