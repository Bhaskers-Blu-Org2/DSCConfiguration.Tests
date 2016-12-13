<#
Comments
#>

<##>
function New-ResourceGroupforTests {
    param(
        [string]$Location = 'EastUS2',
        [string]$ResourceGroupName = "TestAutomation$env:APPVEYOR_PULL_REQUEST_NUMBER",
        [string]$AutomationAccountGroupName = "DSCValidation-$env:APPVEYOR_PULL_REQUEST_NUMBER"
    )
    # Create Resource Group
    $ResourceGroup = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -Force

    # Create Azure Automation account
    $AutomationAccount = New-AzureRMAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountGroupName -Location $Location
}

<##>
Remove-AzureTestResources {
    param(
        [string]$ResourceGroupName = "TestAutomation$env:APPVEYOR_PULL_REQUEST_NUMBER"
    )
    Remove-AzureRmResourceGroup -Name $ResourceGroupName -Force
}

<##>
function Import-ModulesToAzureAutomation {
    param(
        [array]$Modules,
        [string]$ResourceGroupName = $env:APPVEYOR_BUILD_ID,
        [string]$AutomationAccountName = $env:APPVEYOR_PROJECT_NAME
    )
    # Upload required DSC resources (required modules)
    $ImportedModules = @()
    foreach($AutomationModule in $Modules) {
        $ImportedModules += New-AzureRMAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $AutomationModule.Name -ContentLink $AutomationModule.URI
    }

    # The resource modules must finish the "Creating" stage before the configuration will compile successfully
    foreach ($ImportedModule in $ImportedModules)
    {
        while ((Get-AzureRMAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ImportedModule.Name).ProvisioningState -ne 'Succeeded')
        { 
        Start-Sleep -Seconds 15
        }
    }
}

<##>
function Import-ConfigurationToAzureAutomation {
    param(
        [psobject]$Configuration,
        [string]$ResourceGroupName = $env:APPVEYOR_BUILD_ID,
        [string]$AutomationAccountName = $env:APPVEYOR_PROJECT_NAME
    )
    # Import Configuration to Azure Automation DSC
    $ConfigurationImport = Import-AzureRmAutomationDscConfiguration -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -SourcePath $Configuration.Location -Published -Force

    # Load configdata if it exists
    if (Test-Path ".\ConfigurationData\$($Configuration.Name).ConfigData.psd1")
    {
        $ConfigurationData = Import-PowerShellDataFile ".\ConfigurationData\$($Configuration.Name).ConfigData.psd1"
    }

    # Splate params to compile in Azure Automation DSC
    $CompileParams = @{
    ResourceGroupName     = $ResourceGroupName
    AutomationAccountName = $AutomationAccountName
    ConfigurationName     = $Configuration.Name
    ConfigurationData     = $ConfigurationData
    }
    $Compile = Start-AzureRmAutomationDscCompilationJob @CompileParams
}
