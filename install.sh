#!/bin/bash
#
# Compile NotchSpace, l'installe dans /Applications et l'active au démarrage.
#
# Le passage par /Applications n'est pas cosmétique : `SMAppService` exige un
# emplacement stable, et les autorisations (Automation) sont rattachées au chemin
# autant qu'à la signature. Une app relancée depuis un dossier de projet redemande
# ses permissions à chaque déplacement.
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="NotchSpace"
APP="${APP_NAME}.app"
DEST="/Applications/${APP}"

./build.sh

echo "==> Installation dans /Applications"
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    pkill -x "${APP_NAME}" || true
    for _ in $(seq 1 20); do
        pgrep -x "${APP_NAME}" >/dev/null 2>&1 || break
        /bin/sleep 0.1
    done
fi

rm -rf "${DEST}"
cp -R "${APP}" "${DEST}"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "${DEST}" 2>/dev/null || true

echo "==> Lancement au démarrage"
# On écrit directement le LaunchAgent plutôt que de passer par SMAppService :
# celui-ci exige une signature stable, ce qu'une signature ad hoc ne fournit pas.
# L'app lit et écrit le même fichier depuis ses réglages, les deux restent d'accord.
AGENT="${HOME}/Library/LaunchAgents/app.notchspace.NotchSpace.plist"
mkdir -p "$(dirname "${AGENT}")"
cat > "${AGENT}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>app.notchspace.NotchSpace</string>
	<key>ProgramArguments</key>
	<array>
		<string>${DEST}/Contents/MacOS/${APP_NAME}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST
echo "    ${AGENT}"

echo "==> Lancement"
open "${DEST}"

cat <<'EOF'

Installé, et lancé à chaque ouverture de session.
Il reste deux ou trois choses à faire une seule fois :

  1. Autorisations
     Au premier affichage d'un titre, macOS demande l'accès à Spotify et à Chrome.
     Si la fenêtre a été refusée par erreur :
     Réglages Système → Confidentialité et sécurité → Automatisation → NotchSpace

  2. YouTube dans Chrome
     Chrome → menu Affichage → Développeur →
     « Autoriser JavaScript dans les événements AppleScript »
     (désactivé par défaut, sans quoi l'état de lecture reste invisible)

  3. Focus strict (facultatif)
     Réglages de NotchSpace → onglet Focus : la marche à suivre y est détaillée.

Pour ne plus démarrer automatiquement :
     Réglages de NotchSpace → onglet Général

Diagnostic à tout moment :
     /Applications/NotchSpace.app/Contents/MacOS/NotchSpace --diagnose

EOF
