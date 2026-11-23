@{
    RootModule        = 'AzAutomationRuntimeInventory.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b8e4d2a1-6c3f-4e9a-9f2b-1d7c5a3e8b40'
    Author            = 'Cedric Perion'
    CompanyName       = 'Cedric Perion'
    Copyright         = '(c) 2026 Cedric Perion. Licence MIT.'
    Description       = 'Inventaire en lecture seule des runtime environments Azure Automation et de leurs versions de modules, avec import optionnel protege par -Apply.'
    PowerShellVersion = '5.1'
    RequiredModules   = @('Az.Accounts')
    FunctionsToExport = @('Get-RuntimeEnvironmentInventory', 'Set-RuntimeEnvironmentModuleVersion', 'Export-RuntimeEnvironmentReport')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('Azure', 'Automation', 'RuntimeEnvironment', 'MicrosoftGraph', 'PowerShell', 'ReadOnly')
        }
    }
}
