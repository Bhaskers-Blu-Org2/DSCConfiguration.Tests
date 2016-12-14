<#
#>
Describe 'Universal configuration tests' {
    Context 'Module properties' {
        $Name = Get-Item -Path .\ | ForEach-Object -Process {$_.Name}
        $Files = Get-ChildItem
        It 'Contains a module file' {
            $Files.Name.Contains("$Name.psm1") | Should Be True
        }
        It 'Contains a module manifest' {
            $Files.Name.Contains("$Name.psd1") | Should Be True
        }
        It 'Contains a readme' {
            $Files.Name.Contains('README.md') | Should Be True
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
