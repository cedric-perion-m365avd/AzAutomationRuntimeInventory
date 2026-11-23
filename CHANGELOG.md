# Journal des modifications

Le format suit les principes de Keep a Changelog.

## 1.0.0 (2026-11-05)

Première version publique.

Ajouts :

- Get-RuntimeEnvironmentInventory : inventaire en lecture seule des runtime environments et des versions de modules, avec marquage des versions V2.41.0 et V2.41.1 du SDK Microsoft Graph.
- Export-RuntimeEnvironmentReport : rapport HTML simple produit à partir des objets d'inventaire.
- Set-RuntimeEnvironmentModuleVersion : import d'une version précise de module via une requête PUT, inactif par défaut et protégé par le commutateur -Apply ainsi que par SupportsShouldProcess.
