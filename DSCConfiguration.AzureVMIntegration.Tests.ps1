<#
#>
Describe 'Common Tests - Azure VM' -Tag AzureVMIntegration {

    $ResourceGroup = "TestAutomation$env:BuildID"
    $AutomationAccount = "AADSC$env:BuildID"

    $ConfigurationCommands = Get-DSCConfigurationCommands -Module $env:ProjectName
    $OSVersion = (Import-PowerShellDataFile $env:BuildFolder\$env:ProjectName.psd1).PrivateData.PSData.WindowsOSVersion

    $Nodes = Get-AzureRMAutomationDSCNode -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount
    $NodeNames = $Nodes | ForEach-Object {$_.Name}

    Context "Nodes" {
        It "There are as many nodes as configurations" {
            $NodeNames.Count -eq ($ConfigurationCommands.Count * $OSVersion.Count) | Should Be True
        }
    }
}    
