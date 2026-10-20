#!/bin/sh
# ═══════════════════════════════════════════════
#  Installe (ou met à jour) Growth'Lib Desktop sur Mac, sans « Ouvrir quand même ».
#
#  Usage, dans le Terminal :
#    curl -fsSL https://raw.githubusercontent.com/contactliberall/growthlib-desktop-releases/main/install-mac.sh | sh
#
#  Pourquoi : macOS (Gatekeeper) ne bloque une app non notarisée que si elle porte
#  l'attribut de quarantaine, posé par les NAVIGATEURS sur ce qu'ils téléchargent.
#  curl ne le pose pas : l'app installée par ce script s'ouvre directement.
#  Intégrité : empreinte SHA-256 publiée avec chaque version, vérifiée avant
#  installation. Source : contactliberall/growthlib-desktop-releases (public).
#
#  Copie de référence : growthlib-desktop/scripts/install-mac.sh (publiée par
#  scripts/publier-mac.sh à la racine du dépôt des releases).
# ═══════════════════════════════════════════════
set -eu

DEPOT=contactliberall/growthlib-desktop-releases
NOM_APP="Growth'Lib.app"

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
  echo "Growth'Lib Desktop pour Mac nécessite un Mac à puce Apple (M1 à M4)." >&2
  exit 1
fi

TMP=$(mktemp -d)
nettoyer() { hdiutil detach "$TMP/volume" -quiet >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap nettoyer EXIT

echo "→ Recherche de la dernière version…"
curl -fsSL -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$DEPOT/releases?per_page=30" -o "$TMP/releases.json"

# Lecture du JSON avec JavaScript for Automation (présent sur tout Mac, sans Python).
# Même règle que l'app (src/main/updater-mac.js) : plus haute version stable qui
# contient un .dmg Apple Silicon et son empreinte.
CHOIX=$(osascript -l JavaScript - "$TMP/releases.json" <<'JXA'
function run(argv) {
  const texte = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js;
  const lire = (v) => String(v).replace(/^v/, '').split('.').map((n) => parseInt(n, 10) || 0);
  const plusRecente = (a, b) => {
    const x = lire(a), y = lire(b);
    for (let i = 0; i < Math.max(x.length, y.length); i++) {
      if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0);
    }
    return false;
  };
  let meilleure = null;
  for (const r of JSON.parse(texte)) {
    if (r.draft) continue;
    const v = String(r.tag_name || '').replace(/^v/, '');
    if (/-/.test(v)) continue;
    const dmg = (r.assets || []).find((a) => /-mac-arm64\.dmg$/.test(a.name));
    const somme = dmg && (r.assets || []).find((a) => a.name === dmg.name + '.sha256');
    if (!dmg || !somme) continue;
    if (!meilleure || plusRecente(v, meilleure.v)) meilleure = { v, dmg: dmg.browser_download_url, somme: somme.browser_download_url };
  }
  return meilleure ? [meilleure.v, meilleure.dmg, meilleure.somme].join(' ') : '';
}
JXA
)
[ -n "$CHOIX" ] || { echo "Aucune version Mac publiée pour le moment." >&2; exit 1; }
VERSION=$(echo "$CHOIX" | cut -d' ' -f1)
URL_DMG=$(echo "$CHOIX" | cut -d' ' -f2)
URL_SOMME=$(echo "$CHOIX" | cut -d' ' -f3)

echo "→ Téléchargement de Growth'Lib $VERSION…"
curl -fL --progress-bar "$URL_DMG" -o "$TMP/app.dmg"
ATTENDU=$(curl -fsSL "$URL_SOMME" | awk '{print tolower($1)}')
OBTENU=$(shasum -a 256 "$TMP/app.dmg" | awk '{print $1}')
if [ "$ATTENDU" != "$OBTENU" ]; then
  echo "Empreinte SHA-256 incorrecte : téléchargement rejeté, rien n'a été installé." >&2
  exit 1
fi

# /Applications si on peut y écrire, sinon ~/Applications (compte non administrateur).
# (GROWTHLIB_INSTALL_DIR : autre dossier, pour tester sans toucher à l'app installée.)
CIBLE_DOSSIER=${GROWTHLIB_INSTALL_DIR:-/Applications}
if [ ! -w "$CIBLE_DOSSIER" ]; then CIBLE_DOSSIER="$HOME/Applications"; mkdir -p "$CIBLE_DOSSIER"; fi
CIBLE="$CIBLE_DOSSIER/$NOM_APP"

if [ -z "${GROWTHLIB_INSTALL_DIR:-}" ] && pgrep -x "Growth'Lib" >/dev/null 2>&1; then
  echo "→ Fermeture de Growth'Lib en cours d'exécution…"
  osascript -e "quit app \"Growth'Lib\"" >/dev/null 2>&1 || true
  i=0; while pgrep -x "Growth'Lib" >/dev/null 2>&1 && [ $i -lt 30 ]; do sleep 1; i=$((i + 1)); done
fi

echo "→ Installation dans $CIBLE_DOSSIER…"
hdiutil attach -nobrowse -readonly -mountpoint "$TMP/volume" "$TMP/app.dmg" >/dev/null
SOURCE=$(find "$TMP/volume" -maxdepth 1 -name '*.app' | head -1)
[ -n "$SOURCE" ] || { echo "Le .dmg ne contient pas d'application." >&2; exit 1; }
rm -rf "$CIBLE"
ditto "$SOURCE" "$CIBLE"
xattr -dr com.apple.quarantine "$CIBLE" 2>/dev/null || true

if [ -n "${GROWTHLIB_INSTALL_DIR:-}" ]; then echo "✓ Growth'Lib $VERSION installé dans $CIBLE (test : non lancé)."; exit 0; fi
echo "✓ Growth'Lib $VERSION installé. Lancement…"
open "$CIBLE"
