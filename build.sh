#!/bin/bash
#
# Assemble NotchSpace.app sans Xcode.
#
# SwiftPM ne sait produire qu'un exécutable nu : on monte le bundle .app à la main,
# on y injecte l'Info.plist, puis on signe.
#
# Signature : par défaut en ad-hoc (`-`). Le cdhash change à chaque build, donc macOS
# redemande l'autorisation Automation (Spotify / Chrome) après chaque recompilation.
# Pour figer les permissions, créer un certificat auto-signé « Code Signing » dans
# Trousseau d'accès puis exporter son nom :
#
#     export NOTCHSPACE_SIGN_IDENTITY="NotchSpace Dev"
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="NotchSpace"
CONFIG="${CONFIG:-release}"
BUILD_DIR=".build/${CONFIG}"
APP="${APP_NAME}.app"
SIGN_IDENTITY="${NOTCHSPACE_SIGN_IDENTITY:--}"

echo "==> Compilation (${CONFIG})"
swift build -c "${CONFIG}"

# L'app est peut-être en cours d'exécution : on la coupe avant d'écraser le binaire,
# sinon le remplacement échoue ou laisse un processus zombie sur l'ancien code.
if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    echo "==> Arrêt de l'instance en cours"
    pkill -x "${APP_NAME}" || true
    # Laisse à applicationWillTerminate le temps de désactiver le Focus.
    for _ in $(seq 1 20); do
        pgrep -x "${APP_NAME}" >/dev/null 2>&1 || break
        /bin/sleep 0.1
    done
fi

echo "==> Assemblage du bundle"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# Ressources optionnelles (icône, sons). Bundle.main les retrouvera.
if [ -d "Resources/Assets" ]; then
    cp -R "Resources/Assets/." "${APP}/Contents/Resources/"
fi

echo "==> Signature (identité : ${SIGN_IDENTITY})"
codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none "${APP}" 2>&1 | sed 's/^/    /'

# LaunchServices garde en cache l'ancien bundle ; sans ça `open` peut relancer
# la version précédente.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "${APP}" 2>/dev/null || true

echo "==> OK : $(pwd)/${APP}"
