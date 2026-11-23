#Requires -Modules Az.Accounts

# AzAutomationRuntimeInventory
# Module PowerShell de lecture seule par defaut pour inventorier les runtime
# environments Azure Automation et leurs versions de modules. L'import d'une
# version precise reste protege par -Apply et par SupportsShouldProcess.
# Les commentaires et les chaines de ce fichier sont volontairement sans accents
# afin d'eviter tout avertissement d'encodage.

function Get-RuntimeEnvironmentInventory {
    <#
    .SYNOPSIS
        Inventorie en lecture seule les runtime environments d'un compte Azure Automation.

    .DESCRIPTION
        Effectue uniquement des appels GET sur l'API Azure Resource Manager du fournisseur
        Microsoft.Automation afin de lister les runtime environments d'un compte Automation
        puis les packages installes dans chacun. La fonction retourne des objets PowerShell
        et marque les versions V2.41.0 et V2.41.1 du SDK Microsoft Graph PowerShell, documentees
        comme problematiques dans les runtime environments PowerShell 7.2 et 7.4. Aucune ecriture
        n'est effectuee dans le locataire.

    .PARAMETER SubscriptionId
        Identifiant de l'abonnement Azure qui heberge le compte Automation.

    .PARAMETER ResourceGroupName
        Nom du groupe de ressources qui contient le compte Automation.

    .PARAMETER AutomationAccountName
        Nom du compte Azure Automation a inventorier.

    .PARAMETER TenantId
        Identifiant du locataire Azure. Utilise uniquement avec le commutateur -Connect.

    .PARAMETER WatchModule
        Liste de noms de modules a mettre en evidence dans la colonne ASurveiller.

    .PARAMETER ApiVersion
        Version de l'API Azure a utiliser. Par defaut 2023-05-15-preview, soit la version
        citee par la source.

    .PARAMETER Connect
        Ouvre une session Azure avec Connect-AzAccount avant la lecture. Sans ce commutateur
        la fonction utilise la session Azure courante.

    .EXAMPLE
        Get-RuntimeEnvironmentInventory -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-automation-demo' -AutomationAccountName 'aa-demo'

        Liste les runtime environments et leurs versions de modules en utilisant la session Azure courante.

    .EXAMPLE
        Get-RuntimeEnvironmentInventory -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-automation-demo' -AutomationAccountName 'aa-demo' -WatchModule 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users' | Format-Table -AutoSize

        Met en evidence deux modules du SDK Graph et affiche le resultat sous forme de tableau.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SubscriptionId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ResourceGroupName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AutomationAccountName,

        [string] $TenantId,

        [string[]] $WatchModule = @('Microsoft.Graph.Authentication'),

        [string] $ApiVersion = '2023-05-15-preview',

        [switch] $Connect
    )

    if ($Connect.IsPresent) {
        $connectParameters = @{
            Subscription  = $SubscriptionId
            WarningAction = 'SilentlyContinue'
        }
        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            $connectParameters['Tenant'] = $TenantId
        }
        Write-Verbose 'Ouverture d''une session Azure en lecture seule.'
        Connect-AzAccount @connectParameters | Out-Null
    }

    $brokenGraphSdkVersion = @('2.41.0', '2.41.1')
    $basePath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName"

    $environmentPath = "$basePath/runtimeEnvironments?api-version=$ApiVersion"
    Write-Verbose "Lecture des runtime environments : $environmentPath"
    $environmentResponse = Invoke-AzRestMethod -Method Get -Path $environmentPath
    if ($environmentResponse.StatusCode -ne 200) {
        Write-Error "Lecture des runtime environments impossible (HTTP $($environmentResponse.StatusCode))."
        return
    }

    $environments = ($environmentResponse.Content | ConvertFrom-Json).value
    foreach ($environment in $environments) {
        $environmentName = $environment.name
        $encodedName = [System.Uri]::EscapeDataString($environmentName)

        $packagePath = "$basePath/runtimeEnvironments/$encodedName/packages?api-version=$ApiVersion"
        Write-Verbose "Lecture des packages : $packagePath"
        $packageResponse = Invoke-AzRestMethod -Method Get -Path $packagePath
        if ($packageResponse.StatusCode -ne 200) {
            Write-Warning "Lecture des packages impossible pour l'environnement '$environmentName' (HTTP $($packageResponse.StatusCode))."
            continue
        }

        $packages = ($packageResponse.Content | ConvertFrom-Json).value
        foreach ($package in $packages) {
            $moduleVersion = $package.properties.version
            [PSCustomObject]@{
                Environnement        = $environmentName
                Langage              = $environment.properties.runtime.language
                VersionRuntime       = $environment.properties.runtime.version
                Module               = $package.name
                VersionModule        = $moduleVersion
                Etat                 = $package.properties.provisioningState
                ASurveiller          = ($package.name -in $WatchModule)
                VersionProblematique = (($package.name -like 'Microsoft.Graph*') -and ($moduleVersion -in $brokenGraphSdkVersion))
            }
        }
    }
}

function Set-RuntimeEnvironmentModuleVersion {
    <#
    .SYNOPSIS
        Importe une version precise d'un module dans un runtime environment Azure Automation.

    .DESCRIPTION
        Soumet une requete PUT sur l'API Azure Resource Manager du fournisseur Microsoft.Automation
        afin d'importer une version donnee d'un module depuis la PowerShell Gallery vers un runtime
        environment. Cette operation ecrit dans le locataire. Elle reste inactive par defaut et ne
        s'execute que si le commutateur -Apply est fourni. La fonction expose SupportsShouldProcess,
        donc -WhatIf et -Confirm sont pris en charge. Apres soumission elle interroge l'etat
        d'approvisionnement du package jusqu'a Succeeded ou Failed ou l'expiration du delai, comme
        la source le recommande pour du code de production.

    .PARAMETER SubscriptionId
        Identifiant de l'abonnement Azure qui heberge le compte Automation.

    .PARAMETER ResourceGroupName
        Nom du groupe de ressources qui contient le compte Automation.

    .PARAMETER AutomationAccountName
        Nom du compte Azure Automation cible.

    .PARAMETER RuntimeEnvironmentName
        Nom du runtime environment personnalise a mettre a jour.

    .PARAMETER Module
        Un ou plusieurs noms de modules a importer.

    .PARAMETER Version
        Version du module a importer, au format Major.Minor.Patch.

    .PARAMETER TenantId
        Identifiant du locataire Azure. Utilise uniquement avec le commutateur -Connect.

    .PARAMETER ApiVersion
        Version de l'API Azure a utiliser. Par defaut 2023-05-15-preview.

    .PARAMETER TimeoutSecond
        Duree maximale d'attente de la fin de l'approvisionnement, en secondes.

    .PARAMETER PollIntervalSecond
        Intervalle entre deux lectures de l'etat d'approvisionnement, en secondes.

    .PARAMETER Connect
        Ouvre une session Azure avec Connect-AzAccount avant l'operation.

    .PARAMETER Apply
        Execute reellement l'import. Sans ce commutateur la fonction retourne un apercu sans
        rien modifier.

    .EXAMPLE
        Set-RuntimeEnvironmentModuleVersion -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-automation-demo' -AutomationAccountName 'aa-demo' -RuntimeEnvironmentName 'PS74-Graph' -Module 'Microsoft.Graph.Authentication' -Version '2.40.0'

        Retourne un apercu de l'import sans rien modifier car -Apply est absent.

    .EXAMPLE
        Set-RuntimeEnvironmentModuleVersion -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-automation-demo' -AutomationAccountName 'aa-demo' -RuntimeEnvironmentName 'PS74-Graph' -Module 'Microsoft.Graph.Authentication' -Version '2.40.0' -WhatIf

        Montre l'action qui serait executee sans la realiser.

    .EXAMPLE
        Set-RuntimeEnvironmentModuleVersion -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-automation-demo' -AutomationAccountName 'aa-demo' -RuntimeEnvironmentName 'PS74-Graph' -Module 'Microsoft.Graph.Authentication' -Version '2.40.0' -Apply -Confirm:$false

        Importe reellement la version 2.40.0 du module sans demande de confirmation interactive.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $SubscriptionId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ResourceGroupName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AutomationAccountName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RuntimeEnvironmentName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Module,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d+\.\d+\.\d+$')]
        [string] $Version,

        [string] $TenantId,

        [string] $ApiVersion = '2023-05-15-preview',

        [ValidateRange(0, 3600)]
        [int] $TimeoutSecond = 600,

        [ValidateRange(1, 300)]
        [int] $PollIntervalSecond = 15,

        [switch] $Connect,

        [switch] $Apply
    )

    begin {
        $brokenGraphSdkVersion = @('2.41.0', '2.41.1')
        if ($Version -in $brokenGraphSdkVersion) {
            Write-Warning "La version $Version du SDK Microsoft Graph est documentee comme problematique dans les runtime environments PowerShell 7.2 et 7.4."
        }

        if ($Connect.IsPresent) {
            $connectParameters = @{
                Subscription  = $SubscriptionId
                WarningAction = 'SilentlyContinue'
            }
            if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
                $connectParameters['Tenant'] = $TenantId
            }
            Write-Verbose 'Ouverture d''une session Azure.'
            Connect-AzAccount @connectParameters | Out-Null
        }

        $encodedEnvironment = [System.Uri]::EscapeDataString($RuntimeEnvironmentName)
        $basePath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName"
    }

    process {
        foreach ($currentModule in $Module) {
            $encodedModule = [System.Uri]::EscapeDataString($currentModule)
            $packagePath = "$basePath/runtimeEnvironments/$encodedEnvironment/packages/$($encodedModule)/?api-version=$ApiVersion"
            $contentUri = "https://www.powershellgallery.com/api/v2/package/$currentModule/$Version"

            if (-not $Apply.IsPresent) {
                Write-Verbose "Mode lecture seule : aucun import effectue pour $currentModule."
                [PSCustomObject]@{
                    Module        = $currentModule
                    Version       = $Version
                    Environnement = $RuntimeEnvironmentName
                    Action        = 'Apercu'
                    Applique      = $false
                    EtatProvision = $null
                    SourcePackage = $contentUri
                    Message       = 'Relancez avec -Apply pour importer cette version.'
                }
                continue
            }

            $target = "module $currentModule version $Version dans le runtime environment $RuntimeEnvironmentName"
            if (-not $PSCmdlet.ShouldProcess($target, 'Importer depuis la PowerShell Gallery')) {
                [PSCustomObject]@{
                    Module        = $currentModule
                    Version       = $Version
                    Environnement = $RuntimeEnvironmentName
                    Action        = 'WhatIf'
                    Applique      = $false
                    EtatProvision = $null
                    SourcePackage = $contentUri
                    Message       = 'Operation non executee (WhatIf ou refus de confirmation).'
                }
                continue
            }

            $requestBody = @{
                properties = @{
                    contentLink = @{
                        uri = $contentUri
                    }
                }
            } | ConvertTo-Json -Depth 3

            Write-Verbose "Envoi de la requete PUT pour $currentModule."
            $putResponse = Invoke-AzRestMethod -Method Put -Path $packagePath -Payload $requestBody
            if ($putResponse.StatusCode -notin 200, 201, 202) {
                $errorContent = $putResponse.Content | ConvertFrom-Json
                Write-Error "Import de $currentModule en echec (HTTP $($putResponse.StatusCode)) : $($errorContent.Message)"
                continue
            }

            $provisioningState = Wait-RuntimeEnvironmentPackageProvisioning -PackagePath $packagePath -TimeoutSecond $TimeoutSecond -PollIntervalSecond $PollIntervalSecond

            [PSCustomObject]@{
                Module        = $currentModule
                Version       = $Version
                Environnement = $RuntimeEnvironmentName
                Action        = 'Import'
                Applique      = $true
                EtatProvision = $provisioningState
                SourcePackage = $contentUri
                Message       = "Import soumis (HTTP $($putResponse.StatusCode))."
            }
        }
    }
}

function Wait-RuntimeEnvironmentPackageProvisioning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $PackagePath,

        [ValidateRange(0, 3600)]
        [int] $TimeoutSecond = 600,

        [ValidateRange(1, 300)]
        [int] $PollIntervalSecond = 15
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSecond)
    $state = 'Unknown'

    do {
        $response = Invoke-AzRestMethod -Method Get -Path $PackagePath
        if ($response.StatusCode -eq 200) {
            $state = ($response.Content | ConvertFrom-Json).properties.provisioningState
        }
        if ($state -in 'Succeeded', 'Failed') {
            break
        }
        if ((Get-Date) -ge $deadline) {
            Write-Warning "Delai d'attente depasse avant la fin de l'approvisionnement (dernier etat : $state)."
            break
        }
        Start-Sleep -Seconds $PollIntervalSecond
    } while ($true)

    return $state
}

function Export-RuntimeEnvironmentReport {
    <#
    .SYNOPSIS
        Genere un rapport HTML simple a partir des objets d'inventaire.

    .DESCRIPTION
        Recoit par le pipeline les objets produits par Get-RuntimeEnvironmentInventory puis ecrit
        un fichier HTML sur le disque local. La fonction expose SupportsShouldProcess, donc -WhatIf
        et -Confirm sont pris en charge. Elle n'ecrit rien dans le locataire Azure.

    .PARAMETER InputObject
        Objets d'inventaire a inclure dans le rapport.

    .PARAMETER Path
        Chemin du fichier HTML a creer.

    .PARAMETER Title
        Titre affiche en tete du rapport.

    .EXAMPLE
        Get-RuntimeEnvironmentInventory -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-automation-demo' -AutomationAccountName 'aa-demo' | Export-RuntimeEnvironmentReport -Path './inventaire.html'

        Produit un rapport HTML de l'inventaire courant.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject[]] $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [string] $Title = 'Inventaire des runtime environments Azure Automation'
    )

    begin {
        $collected = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        foreach ($item in $InputObject) {
            $collected.Add($item)
        }
    }

    end {
        if ($collected.Count -eq 0) {
            Write-Warning 'Aucune donnee a exporter.'
            return
        }

        if ($PSCmdlet.ShouldProcess($Path, 'Ecrire le rapport HTML')) {
            $headContent = @'
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 2rem; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #cccccc; padding: 6px 10px; text-align: left; }
th { background-color: #f2f2f2; }
</style>
'@
            $reportHtml = $collected |
                ConvertTo-Html -Title $Title -Head $headContent -PreContent "<h1>$Title</h1>" |
                Out-String
            Set-Content -Path $Path -Value $reportHtml -Encoding UTF8
            Get-Item -Path $Path
        }
    }
}

Export-ModuleMember -Function @(
    'Get-RuntimeEnvironmentInventory',
    'Set-RuntimeEnvironmentModuleVersion',
    'Export-RuntimeEnvironmentReport'
)
