<#
#>
Describe 'Common Tests - Azure VM' -Tag AzureVMIntegration {

    $ResourceGroup = "TestAutomation$env:BuildID"
    $AutomationAccount = "DSCValidation$env:BuildID"

    $ConfigurationCommands = Get-DSCConfigurationCommands

    $Nodes = Get-AzureRMAutomationDSCNode -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount
    $NodeNames = $Nodes | ForEach-Object {$_.Name}

    Context "Nodes" {
        It "There are as many nodes as configurations" {
            $NodeNames.Count -eq $ConfigurationCommands.Count | Should Be True
        }
    }
}    
