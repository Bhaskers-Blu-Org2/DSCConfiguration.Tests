<#
#>
Describe 'Universal configuration tests' {
    Context 'Module properties' {
        $Name = Get-Item -Path .\ | ForEach-Object -Process {$_.Name}
        $Files = Get-ChildItem
        It 'Contains a module file that aligns to the folder name' {
            $Files.Name.Contains("$Name.psm1") | Should Be True
        }
        It 'Contains a module manifest that aligns to the folder and module names' {
            $Files.Name.Contains("$Name.psd1") | Should Be True
        }
        It 'Contains a readme' {
            $Files.Name.Contains('README.md') | Should Be True
        }
        It 'Mainfest should import as a data file' {
            $Manifest = Import-PowerShellDataFile -Path $Name.psd1 | Should Not Throw
        }
        It 'Should point to the root module in the manifest' {
            $Manifest.RootModule | Should Be ".\$Name.psm1"
        }
        It 'Should have a GUID in the manifest' {
            $Mainfest.GUID | Should Match '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'
        }
    }
}

# psd1 should import

# manifest should have name, id, root mod

# requirements should be found in gallery

# requirements should install locally

# each configuration should compile locally

# each configuration should produce a mof

# after:
# technically are these unit or integration?

# modules should be in AADSC

# modules should show extracted activities

# configurations should be in AADSC

# configurations should show as compiled
