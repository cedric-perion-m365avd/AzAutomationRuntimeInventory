# AzAutomationRuntimeInventory

Module PowerShell de lecture seule qui inventorie les runtime environments d'un compte Azure Automation et les versions de modules qui y sont installées. Il signale aussi les versions du SDK Microsoft Graph PowerShell connues comme problématiques dans les runtime environments PowerShell 7.2 et 7.4.

## Pourquoi maintenant

Une mise à jour du SDK Microsoft Graph PowerShell a introduit un défaut de chargement des assemblages. Selon la source citée, les versions V2.41.0 et V2.41.1 empêchaient le cmdlet Connect-MgGraph de se charger dans les runtime environments PowerShell 7.2 et 7.4 d'Azure Automation. Comme les cmdlets du SDK Graph exigent une authentification pour s'exécuter, chaque runbook basé sur le SDK s'arrêtait net. La source indique que Microsoft a publié la version V2.41.2 le 14 octobre 2026 pour corriger le problème.

La parade durable décrite par la source ne dépend pas d'un correctif ponctuel. Elle consiste à maintenir deux runtime environments personnalisés distincts : un environnement Production figé sur une version stable éprouvée et un environnement Current avec les versions les plus récentes. Avant de figer ou de mettre à jour un environnement il faut d'abord savoir ce qui tourne déjà. Ce module répond à cette première étape : lire et comparer l'existant.

## Ce que fait le module

- Get-RuntimeEnvironmentInventory lit la liste des runtime environments du compte Automation puis les packages de chacun au moyen d'appels GET sur l'API Azure 2023-05-15-preview. Il retourne des objets PowerShell et marque les versions V2.41.0 et V2.41.1 du SDK Graph.
- Export-RuntimeEnvironmentReport reçoit ces objets et produit un rapport HTML simple sur le disque local.
- Set-RuntimeEnvironmentModuleVersion importe une version précise d'un module depuis la PowerShell Gallery vers un runtime environment au moyen d'une requête PUT. Cette fonction écrit dans le locataire. Elle reste donc inactive par défaut et n'agit que si vous ajoutez le commutateur -Apply. Elle expose SupportsShouldProcess donc les commutateurs -WhatIf et -Confirm fonctionnent.

## Prérequis

- PowerShell 5.1 ou PowerShell 7 avec le module Az.Accounts installé.
- Une session Azure ouverte avec Connect-AzAccount ou le commutateur -Connect des fonctions.
- Pour l'inventaire en lecture seule : le rôle Azure RBAC Lecteur (Reader) sur le compte Automation visé, comme l'indique la source.
- Pour l'import avec -Apply : un rôle Azure RBAC autorisant l'écriture sur les runtime environments du compte Automation (par exemple Contributeur).
- Ce module n'appelle pas Microsoft Graph. Il interroge l'API Azure Resource Manager du fournisseur Microsoft.Automation au moyen de Invoke-AzRestMethod. Aucune permission Microsoft Graph n'est donc requise.

## Installation

```powershell
Import-Module ./AzAutomationRuntimeInventory.psd1
```

Vous pouvez aussi déposer le dossier du module dans un des chemins de $env:PSModulePath pour qu'il se charge automatiquement.

## Exemples d'utilisation

Les identifiants ci-dessous sont fictifs. Remplacez-les par les vôtres.

Inventaire simple avec la session Azure courante :

```powershell
Connect-AzAccount -Subscription '00000000-0000-0000-0000-000000000000'
Get-RuntimeEnvironmentInventory -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-automation-demo' -AutomationAccountName 'aa-demo' | Format-Table -AutoSize
```

Mise en évidence de plusieurs modules puis rapport HTML :

```powershell
Get-RuntimeEnvironmentInventory -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-automation-demo' -AutomationAccountName 'aa-demo' -WatchModule 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Users' | Export-RuntimeEnvironmentReport -Path './inventaire.html'
```

Import d'une version précise. Vérifiez d'abord avec -WhatIf puis appliquez avec -Apply :

```powershell
Set-RuntimeEnvironmentModuleVersion -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-automation-demo' -AutomationAccountName 'aa-demo' -RuntimeEnvironmentName 'PS74-Graph' -Module 'Microsoft.Graph.Authentication' -Version '2.40.0' -WhatIf

Set-RuntimeEnvironmentModuleVersion -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-automation-demo' -AutomationAccountName 'aa-demo' -RuntimeEnvironmentName 'PS74-Graph' -Module 'Microsoft.Graph.Authentication' -Version '2.40.0' -Apply
```

Pour une exécution non interactive dans un runbook ajoutez -Confirm:$false au dernier appel.

## Exemple de sortie (fictif)

Le tableau ci-dessous est une illustration fictive. Les valeurs réelles dépendent de vos environnements.

```
Environnement Langage    VersionRuntime Module                         VersionModule Etat      ASurveiller VersionProblematique
------------- -------    -------------- ------                         ------------- ----      ----------- --------------------
PS74-Current  PowerShell 7.4            Microsoft.Graph.Authentication 2.41.1        Succeeded True        True
PS74-Graph    PowerShell 7.4            Microsoft.Graph.Authentication 2.40.0        Succeeded True        False
PS74-Graph    PowerShell 7.4            Microsoft.Graph.Users          2.40.0        Succeeded False       False
```

## Limites connues

- L'API 2023-05-15-preview est une préversion. Son schéma de réponse peut évoluer. Les noms de propriétés lus (properties.runtime.version et properties.version) méritent d'être validés contre la réponse réelle de votre locataire avant toute automatisation. Le paramètre -ApiVersion permet d'indiquer une autre version d'API.
- Les versions de modules affichées dépendent de vos environnements. Les exemples de versions cités ici sont illustratifs.
- Set-RuntimeEnvironmentModuleVersion soumet un import puis interroge l'état d'approvisionnement jusqu'à Succeeded ou Failed ou l'expiration du délai. Un état Succeeded confirme la fin de l'import côté Azure selon l'API.
- Ce module n'a pas été exécuté lors de la préparation de ce dépôt. Validez-le dans un environnement de test avant tout usage en production.

## Liens

- Article : https://trivium365.com/blog/azure-automation-inventorier-runtime-environments-sdk-graph/
- Source citée par l'article : Maintaining Stable Azure Automation Runtime Environments, office365itpros.com, https://office365itpros.com/2026/10/12/maintain-runtime-environments-ps/


## Démonstration en vidéo

https://www.youtube.com/watch?v=Oi3b1iHHREA
