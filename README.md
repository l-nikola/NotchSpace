# NotchSpace

Une app macOS qui transforme l'encoche du MacBook en surface utile :

- **Minuteur Pomodoro** dessiné autour de la forme de l'encoche
- **Lecture en cours** (Spotify, YouTube) avec contrôles rapides
- **Étagère** pour glisser-déposer des fichiers en transit

L'app se déplie au survol de l'encoche et se referme quand vous partez.

## Installation

```bash
git clone https://github.com/l-nikola/NotchSpace notchspace
````

```bash
./install.sh
```

Ce script compile l'app, l'installe dans `/Applications`, la lance et
l'active au démarrage de session.

Pour juste compiler, sans installer :

```bash
./build.sh && open NotchSpace.app
```

## Autorisations

Au premier usage, macOS va demander :

- l'**automatisation** de Spotify et Chrome (pour lire l'état de lecture)
- pour YouTube dans Chrome, activer manuellement : menu **Affichage → Développeur
  → Autoriser JavaScript dans les événements AppleScript**

