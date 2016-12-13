<#
Comments
#>

$env:ResourceGroupName = 'TestAutomation'+$env:APPVEYOR_PULL_REQUEST_NUMBER
$env:AutomationAccountName = 'DSCValidation'+$env:APPVEYOR_PULL_REQUEST_NUMBER

<##>
function New-ResourceGroupforTests {
    param(
        [string]$Location = 'EastUS2',
        [string]$ResourceGroupName = $env:ResourceGroupName,
        [string]$AutomationAccountName = $env:AutomationAccountName
    )
    try {
        # Create Resource Group
        $ResourceGroup = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -Force

        # Create Azure Automation account
        $AutomationAccount = New-AzureRMAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName -Location $Location

        if ($Account = Get-AzureRmAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName) {
            return $true
        }
        else {
            return $false
        }
    }
    catch [System.Exception] {
        throw "A failure occured while creating the Resource Group or Auatomation Account`n$error"
    }
}

<##>
function Remove-AzureTestResources {
    param(
        [string]$ResourceGroupName = $env:ResourceGroupName
    )
    try {
        $Remove = Remove-AzureRmResourceGroup -Name $ResourceGroupName -Force
    }
    catch [System.Exception] {
        throw "An error occured while removing the Resource Group or Auatomation Account`n$error"
    }
}

<#
TODO should catch issues with import and return to build log
#>
function Import-ModulesToAzureAutomation {
    param(
        [array]$Modules,
        [string]$ResourceGroupName = $env:ResourceGroupName,
        [string]$AutomationAccountName = $env:AutomationAccountName
    )
    try {
        # Upload required DSC resources (required modules)
        $ImportedModules = @()
        foreach($AutomationModule in $Modules) {
            $ImportedModules += New-AzureRMAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $AutomationModule.Name -ContentLink $AutomationModule.URI
        }
        return $true
    }
    catch [System.Exception] {
        throw "An error occured while importing the modules to Azure Automation`n$error"
    }
}

<#
TODO should have max time
#>
function Wait-ModuleExtraction {
    param(
        [array]$Modules,
        [string]$ResourceGroupName = $env:ResourceGroupName,
        [string]$AutomationAccountName = $env:AutomationAccountName
    )
    try {
        # The resource modules must finish the "Creating" stage before the configuration will compile successfully
        foreach ($ImportedModule in $ImportedModules) {
            while ((Get-AzureRMAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $ImportedModule.Name).ProvisioningState -ne 'Succeeded') {
            Start-Sleep -Seconds 15
            }
        }
        return $true
    }
    catch [System.Exception] {
        throw "An error occured while waiting for module activities to extract in Azure Automation`n$error"        
    }
}    

<#
TODO - the timer should catch issues with compilation and return to build log
#>
function Import-ConfigurationToAzureAutomation {
    param(
        [psobject]$Configuration,
        [string]$ResourceGroupName = $env:ResourceGroupName,
        [string]$AutomationAccountName = $env:AutomationAccountName
    )
    try {
            # Import Configuration to Azure Automation DSC
            $ConfigurationImport = Import-AzureRmAutomationDscConfiguration -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -SourcePath $Configuration.Location -Published -Force

            # Load configdata if it exists
            if (Test-Path ".\ConfigurationData\$($Configuration.Name).ConfigData.psd1") {
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
        while ((Get-AzureRmAutomationDscCompilationJob -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Configuration.Name).Status -ne 'Completed') {
            Start-Sleep -Seconds 15
            }
        return $true
    }
    catch [System.Exception] {
        throw "An error occured while importing or compiling the configurations using Azure Automation`n$error"        
    }
}
