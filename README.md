# Vencord AutoUpdate

![Windows](https://img.shields.io/badge/Windows-10%20%2F%2011-blue?style=flat-square)
![PowerShell 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE?style=flat-square)
![Licence MIT](https://img.shields.io/badge/Licence-MIT-green?style=flat-square)
[![Vérification](https://github.com/9Chrk/Vencord-AutoUpdate/actions/workflows/verify.yml/badge.svg)](https://github.com/9Chrk/Vencord-AutoUpdate/actions/workflows/verify.yml)

Vencord AutoUpdate est un outil de **réparation automatique de Vencord après les mises à jour de Discord**, développé en **PowerShell pour Windows**. Il surveille votre installation de Discord Stable, réapplique Vencord avec son installateur officiel lorsque nécessaire, puis relance Discord s’il était ouvert.

La surveillance fonctionne en arrière-plan et démarre avec votre session Windows. Les chemins par défaut sont déduits de votre compte utilisateur ; vous pouvez adapter les délais et le comportement dans un fichier de configuration local.

> Projet indépendant, sans affiliation avec Discord ou Vencord. La modification de Discord est confiée à l’installateur officiel de Vencord.

---

## 📖 Sommaire

- [Fonctionnalités](#fonctionnalites)
- [Prérequis](#prerequis)
- [Installation](#installation)
- [Configuration](#configuration)
- [Lancement et utilisation](#lancement-et-utilisation)
- [Désactivation](#desactivation)
- [Données et confidentialité](#donnees-et-confidentialite)
- [Flux général](#flux-general)
- [Structure du projet](#structure-du-projet)
- [Tests](#tests)
- [Problèmes fréquents](#problemes-frequents)
- [Contribuer](#contribuer)
- [Licence et crédits](#licence-et-credits)

<a id="fonctionnalites"></a>

## ✨ Fonctionnalités

- **Détection des mises à jour** : surveille les dossiers `app-*` de Discord Stable et mémorise la dernière version vérifiée.
- **Réparation automatique** : intervient lorsque Vencord est absent, que ses fichiers requis sont incomplets ou que la version de Discord a changé.
- **Installateur officiel** : récupère la dernière version de `VencordInstallerCli.exe` depuis le dépôt Vencord et compare son SHA-256 à l’empreinte publiée par GitHub avant de l’exécuter.
- **Attente de stabilité** : attend que les fichiers surveillés soient stables et qu’aucun processus de mise à jour identifié ne soit actif avant d’intervenir.
- **Relance de Discord** : ferme Discord pour la réparation et le rouvre s’il était lancé. Ce comportement peut être désactivé pour attendre une fermeture manuelle.
- **Démarrage automatique** : crée une tâche Windows propre à l’utilisateur connecté, sans mot de passe enregistré ni demande d’exécution en administrateur.
- **Journaux locaux** : conserve les résultats de réparation et réessaie après une erreur, sans multiplier les interventions sur une installation saine.

Les mises à jour de Vencord publiées sans changement de Discord restent gérées par le mécanisme de mise à jour de Vencord lui-même.

<a id="prerequis"></a>

## 🧰 Prérequis

- **Windows 10 ou 11** avec une session utilisateur ouverte.
- **Discord Stable pour Windows**, installé normalement depuis [discord.com](https://discord.com/download). Le dossier doit contenir des sous-dossiers `app-<version>`.
- **Windows PowerShell 5.1**, le **Planificateur de tâches** et **Windows Script Host avec VBScript** (`wscript.exe`). VBScript doit être disponible et autorisé sur votre système.
- Une **connexion Internet** lors d’une réparation pour récupérer l’installateur et les fichiers officiels Vencord.
- Un dossier de projet accessible en écriture par votre compte Windows.

Aucun environnement Python, Node.js ou Go n’est nécessaire. Vous n’avez pas besoin de copier un installateur Vencord personnel dans le dépôt : le script télécharge la variante CLI officielle.

Le projet cible **Discord Stable sous Windows**. Les éditions PTB/Canary, Microsoft Store, les installations sans dossiers `app-*`, macOS et Linux ne sont pas prises en charge par cette version.

<a id="installation"></a>

## 📦 Installation

### 1. Récupérer le projet

Avec Git, ouvrez un terminal dans le dossier où vous souhaitez conserver le projet :

```powershell
git clone https://github.com/9Chrk/Vencord-AutoUpdate.git
cd Vencord-AutoUpdate
```

Sans Git, utilisez **Code → Download ZIP** sur cette page, puis extrayez **tout le contenu** de l’archive dans un dossier permanent. Ouvrez ensuite un terminal dans ce dossier. N’exécutez pas les scripts directement depuis le ZIP.

### 2. Préparer la configuration

```powershell
Copy-Item .\config.example.json .\config.json
```

Les valeurs fournies conviennent à une installation classique de Discord. Pour un autre emplacement ou pour éviter les redémarrages automatiques, adaptez `config.json` selon la section [Configuration](#configuration).

### 3. Vérifier l’installation détectée

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Watch-Vencord.ps1 -CheckOnly
```

Cette commande affiche la version de Discord, son chemin et la présence de Vencord. Elle ne ferme pas Discord et n’applique aucune réparation. `VencordPatched: False` indique qu’une réparation sera nécessaire ; un message indiquant qu’aucune version complète n’a été détectée demande de vérifier le chemin ou de terminer l’installation de Discord.

### 4. Activer la surveillance

Depuis un terminal **normal, sans « Exécuter en tant qu’administrateur »** :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-AutoUpdate.ps1
```

Le script crée et démarre la tâche **Vencord AutoUpdate** pour votre compte Windows. Elle se relance à chaque ouverture de session, fonctionne sur batterie et n’a pas de limite de durée. Si `config.json` n’existe pas encore, il est créé depuis l’exemple.

> La première activation peut réparer Vencord immédiatement après le délai de stabilité. Avec `restartDiscord: true`, Discord sera fermé puis relancé s’il était ouvert : cela peut interrompre un appel en cours.

L’option `-ExecutionPolicy Bypass` concerne uniquement le processus PowerShell lancé par ces commandes. Elle ne modifie pas la stratégie d’exécution globale de Windows et ne contourne pas les règles imposées par une organisation.

<a id="configuration"></a>

## ⚙️ Configuration

Les réglages publics figurent dans [`config.example.json`](config.example.json). Votre copie `config.json` est locale et ignorée par Git.

```json
{
  "discordPath": "%LOCALAPPDATA%\\Discord",
  "pollSeconds": 15,
  "settleSeconds": 30,
  "retrySeconds": 300,
  "restartDiscord": true
}
```

| Paramètre | Valeur par défaut | Rôle |
| --- | --- | --- |
| `discordPath` | `%LOCALAPPDATA%\Discord` | Dossier parent de Discord ; `%LOCALAPPDATA%` est développé pour l’utilisateur connecté. |
| `pollSeconds` | `15` | Intervalle entre les vérifications, de 1 à 60 secondes. |
| `settleSeconds` | `30` | Durée de stabilité exigée, de 5 à 300 secondes. |
| `retrySeconds` | `300` | Délai avant une nouvelle tentative après une erreur, de 10 à 3 600 secondes. |
| `restartDiscord` | `true` | Autorise la fermeture puis la relance de Discord pour une réparation. Avec `false`, attend que vous fermiez Discord. |

### Discord installé ailleurs

Remplacez uniquement `discordPath` par le dossier qui contient `Update.exe` et les dossiers `app-*`. Par exemple :

```json
"discordPath": "D:\\Applications\\Discord"
```

Dans un fichier JSON, les antislashs doivent être doublés. Ne pointez ni vers `Discord.exe`, ni vers un dossier `app-<version>`, car ce numéro change à chaque mise à jour.

### Appliquer une modification

Après avoir modifié `config.json`, relancez la commande d’installation. Elle arrête proprement la surveillance existante, attend la fin d’une éventuelle réparation, puis la redémarre avec les nouveaux réglages.

Les fichiers Vencord sont recherchés selon les variables utilisées par l’installateur officiel : `VENCORD_USER_DATA_DIR` si elle est définie, sinon le dossier voisin `VencordData` lorsque `DISCORD_USER_DATA_DIR` est défini, sinon `%APPDATA%\Vencord`. Une variable personnalisée doit être disponible dans la session où la tâche s’exécute.

<a id="lancement-et-utilisation"></a>

## ▶️ Lancement et utilisation

Après activation, utilisez Discord normalement. La tâche vérifie son installation en arrière-plan ; il n’y a pas de fenêtre de surveillance à garder ouverte.

Avec les réglages par défaut, une intervention peut commencer après environ **30 à 45 secondes de stabilité**, auxquelles s’ajoutent le téléchargement et la réparation. Il ne s’agit pas d’une garantie de délai : une mise à jour encore active ou une erreur réseau reporte l’intervention.

Commandes utiles depuis la racine du projet :

```powershell
# Vérifier Discord et Vencord, sans les modifier.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Watch-Vencord.ps1 -CheckOnly

# Lire les derniers événements.
Get-Content .\runtime\watcher.log -Tail 30

# Afficher la tâche dans le planificateur.
Get-ScheduledTask -TaskName 'Vencord AutoUpdate'

# Vérifier une fois et réparer si nécessaire, puis quitter.
# À utiliser lorsque la surveillance automatique est désactivée.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Watch-Vencord.ps1 -Once
```

Le mode `-Once` attend une installation complète et stable ; il peut rester en attente si Discord est absent ou si une mise à jour continue. Une seconde surveillance lancée depuis le même dossier quitte immédiatement si la première détient déjà le verrou.

Conservez le dossier du projet à son emplacement tant que la tâche est active. Pour le déplacer, désactivez d’abord l’automatisation, déplacez le dossier, puis relancez l’installation depuis son nouvel emplacement. Utilisez une seule copie active du projet par compte Windows.

<a id="desactivation"></a>

## ⏹️ Désactivation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-AutoUpdate.ps1
```

Le script demande l’arrêt de la surveillance, attend la fin d’une éventuelle réparation et supprime la tâche Windows. **Discord et Vencord restent installés.** Vous pouvez ensuite supprimer le dossier du projet.

Utilisez ce script pour désactiver l’outil : arrêter seulement la tâche dans le planificateur peut laisser son processus enfant actif. L’arrêt propre peut prendre plusieurs minutes si une opération réseau ou une réparation est en cours.

<a id="donnees-et-confidentialite"></a>

## 🗃️ Données et confidentialité

Le dossier `runtime/` est créé localement au premier lancement de la surveillance :

| Fichier | Contenu |
| --- | --- |
| `VencordInstallerCli.exe` | Installateur officiel téléchargé et vérifié. |
| `state.json` | Dernière version de Discord vérifiée et date de vérification. |
| `watcher.log` | Démarrages, réparations, arrêts et erreurs de la surveillance. |
| `installer.stdout.log` / `installer.stderr.log` | Sortie de la dernière réparation. |
| `watcher.lock` | Verrou empêchant deux surveillances dans le même dossier. |

Le journal principal tourne à environ 2 Mio et conserve une copie précédente. La configuration personnelle, les journaux, l’installateur téléchargé et les fichiers temporaires de test sont ignorés par Git.

Les journaux peuvent contenir votre chemin utilisateur. Relisez et anonymisez leur contenu avant de le joindre à une issue. Aucun jeton GitHub ni identifiant Discord n’est demandé par ces scripts.

<a id="flux-general"></a>

## 🧬 Flux général

```text
Ouverture de la session Windows
  → tâche Vencord AutoUpdate
  → surveillance du dossier Discord configuré
  → nouvelle version ou patch Vencord manquant
  → attente de stabilité et vérification de l’updater
  → récupération de l’installateur officiel + contrôle SHA-256
  → fermeture de Discord si autorisée et nécessaire
  → réparation avec --repair --location
  → vérification du chargeur et des fichiers Vencord
  → relance de Discord s’il était ouvert
  → mémorisation de la version vérifiée
```

Une réparation réussie exige un code de sortie valide, le message de patch de l’installateur, la sauvegarde `_app.asar`, un chargeur pointant vers le bon `patcher.js` et les quatre fichiers Vencord requis non vides. Un simple code de sortie zéro ne suffit pas.

L’attente de stabilité réduit le risque de conflit avec une mise à jour ; elle ne constitue pas un verrou partagé avec Discord. Si le format d’installation ou le comportement du CLI officiel change, une adaptation du script peut être nécessaire.

<a id="structure-du-projet"></a>

## 📂 Structure du projet

```text
.
├── .github/workflows/verify.yml  # Vérification sous Windows PowerShell
├── config.example.json          # Configuration publique et générique
├── Install-AutoUpdate.ps1        # Création et démarrage de la tâche Windows
├── Launch-Watcher.vbs           # Lancement de PowerShell sans fenêtre
├── Watch-Vencord.ps1            # Boucle de surveillance et état local
├── VencordAutoUpdate.psm1       # Configuration, détection et réparation
├── Stop-Watcher.ps1             # Arrêt propre après l’opération en cours
├── Uninstall-AutoUpdate.ps1      # Arrêt et suppression de la tâche
├── tests/Verify-AutoUpdate.ps1   # Tests sur installations factices
├── LICENSE                      # Licence MIT des scripts
└── README.md                    # Installation et utilisation
```

`config.json` et `runtime/` sont créés sur votre PC et ne sont pas publiés dans le dépôt.

<a id="tests"></a>

## 🧪 Tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Verify-AutoUpdate.ps1
```

Les tests créent des fichiers factices dans `tests/.tmp/`, remplacent les appels de réparation par des simulations et nettoient leur dossier à la fin. Ils ne ferment pas votre Discord, n’exécutent pas l’installateur réel et n’accèdent pas au réseau.

Ils couvrent la configuration générique et locale, les paramètres invalides, le ciblage des versions, les installations incomplètes, la détection du chargeur Vencord, les chemins contenant des espaces ou une apostrophe, les processus terminés et les faux succès de réparation. Le workflow GitHub Actions vérifie également la syntaxe PowerShell.

Un cycle réel de fermeture, réparation et relance a été vérifié sous Windows sur Discord Stable. Les tests simulant un changement de version ne remplacent pas l’observation d’une future mise à jour réelle de Discord et ne garantissent pas le fonctionnement de chaque plugin Vencord.

<a id="problemes-frequents"></a>

## ❗ Problèmes fréquents

| Problème | Vérification ou solution |
| --- | --- |
| Aucune version complète de Discord détectée | Terminez l’installation ou la mise à jour de Discord ; vérifiez que `discordPath` vise le dossier parent contenant `app-*`. |
| La commande ne trouve pas un script | Ouvrez le terminal à la racine du projet extrait et vérifiez que tous les fichiers sont présents. |
| Discord est fermé pendant un appel | C’est le comportement de `restartDiscord: true`. Passez à `false`, puis relancez l’installation pour attendre une fermeture manuelle. |
| La réparation attend alors que Discord paraît fermé | Quittez aussi Discord depuis son icône dans la zone de notification ; sa fenêtre peut être fermée alors que ses processus restent actifs. |
| Erreur réseau ou limitation GitHub | Consultez les journaux. La surveillance réessaie après `retrySeconds` ; aucun jeton GitHub n’est nécessaire. |
| `wscript.exe` ou VBScript indisponible | Vérifiez la disponibilité du composant VBScript et les règles de votre système. Sans lui, le lancement silencieux de cette version ne peut pas fonctionner. |
| Accès refusé au planificateur ou à un fichier | Utilisez votre session habituelle et un dossier accessible en écriture. Sur un PC administré, les règles de l’organisation peuvent empêcher cette automatisation. |
| La tâche ne démarre plus après un déplacement | Désactivez la tâche depuis l’ancien emplacement avant de déplacer le dossier, puis installez-la depuis le nouvel emplacement. |
| Vencord reste absent malgré une réparation annoncée | Consultez les deux journaux de l’installateur et essayez son interface officielle. Joignez une version anonymisée des erreurs à une issue. |

<a id="contribuer"></a>

## 🤝 Contribuer

Les corrections et améliorations sont les bienvenues. Pour signaler un problème, précisez votre version de Windows, la version de Discord, les paramètres utiles sans chemin personnel et les erreurs anonymisées.

Avant de proposer une modification, exécutez les tests sur fichiers factices. Pour toute modification du cycle de réparation, distinguez les résultats simulés des vérifications réellement effectuées dans Discord.

<a id="licence-et-credits"></a>

## 📜 Licence et crédits

Les scripts de ce dépôt sont distribués sous licence [MIT](LICENSE).

[Vencord](https://github.com/Vendicated/Vencord) et son [installateur officiel](https://github.com/Vencord/Installer) sont des projets distincts, soumis à leurs propres licences. Leurs exécutables ne sont pas redistribués dans ce dépôt.

- [Téléchargement officiel de Vencord](https://vencord.dev/download)
- [Versions de l’installateur](https://github.com/Vencord/Installer/releases)
- [Options du CLI et réparation](https://github.com/Vencord/Installer/blob/main/cli.go)
