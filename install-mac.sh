#!/bin/sh
# ═══════════════════════════════════════════════
#  Installe (ou met à jour) LibPilot Desktop sur Mac, sans « Ouvrir quand même ».
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
NOM_APP="LibPilot.app"

echec() { echo "$1" >&2; exit 1; }

# Vérification du Mac, en phrases simples. (GROWTHLIB_SYSTEME_SIMULE, GROWTHLIB_PUCE_SIMULEE et GROWTHLIB_TEST_GARDE ne servent
# qu'aux tests automatiques : ils permettent d'essayer ces messages sans Mac Intel.)
SYSTEME=${GROWTHLIB_SYSTEME_SIMULE:-$(uname -s)}
if [ -n "${GROWTHLIB_PUCE_SIMULEE:-}" ]; then
  PUCE=${GROWTHLIB_PUCE_SIMULEE}
else
  PUCE=$(uname -m)
  # Terminal ouvert « avec Rosetta » : uname répond x86_64 sur un Mac à puce Apple ; cette ligne dit la vérité.
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ]; then PUCE=arm64; fi
fi
if [ "${SYSTEME}" != Darwin ]; then
  echec "Cette commande sert à installer LibPilot sur un Mac. Pour Windows, téléchargez le fichier d'installation sur la page des versions."
fi
if [ "${PUCE}" != arm64 ]; then
  echo "Ce Mac a un processeur Intel : LibPilot ne fonctionne pas encore sur ce type de Mac." >&2
  echo "Rien n'a été installé ni modifié sur votre Mac." >&2
  echo "Pour vérifier : menu Apple (la pomme), « À propos de ce Mac », ligne « Puce » ou « Processeur »." >&2
  echo "LibPilot fonctionne sur les Mac à puce Apple (M1, M2, M3, M4). Besoin d'aide ? Contactez votre conseiller LibPilot." >&2
  exit 1
fi
if [ -n "${GROWTHLIB_TEST_GARDE:-}" ]; then echo "Ce Mac est compatible."; exit 0; fi

TMP=$(mktemp -d)
nettoyer() { hdiutil detach "${TMP}/volume" -quiet >/dev/null 2>&1 || true; rm -rf "${TMP}"; }
trap nettoyer EXIT

echo "→ Recherche de la dernière version…"
curl -fsSL -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${DEPOT}/releases?per_page=30" -o "${TMP}/releases.json" \
  || echec "Impossible de joindre le site de téléchargement. Vérifiez votre connexion internet, puis recommencez la commande."

# Lecture du JSON avec JavaScript for Automation (présent sur tout Mac, sans Python).
# Même règle que l'app (src/main/updater-mac.js) : plus haute version stable qui
# contient un .dmg Apple Silicon et son empreinte.
CHOIX=$(osascript -l JavaScript - "${TMP}/releases.json" <<'JXA'
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
[ -n "${CHOIX}" ] || echec "Aucune version de LibPilot pour Mac n'est disponible pour le moment. Contactez votre conseiller LibPilot."
VERSION=$(echo "${CHOIX}" | cut -d' ' -f1)
URL_DMG=$(echo "${CHOIX}" | cut -d' ' -f2)
URL_SOMME=$(echo "${CHOIX}" | cut -d' ' -f3)

echo "→ Téléchargement de LibPilot ${VERSION}…"
curl -fL --progress-bar "${URL_DMG}" -o "${TMP}/app.dmg" \
  || echec "Impossible de joindre le site de téléchargement. Vérifiez votre connexion internet, puis recommencez la commande."
ATTENDU=$(curl -fsSL "${URL_SOMME}" | awk '{print tolower($1)}') \
  || echec "Impossible de joindre le site de téléchargement. Vérifiez votre connexion internet, puis recommencez la commande."
OBTENU=$(shasum -a 256 "${TMP}/app.dmg" | awk '{print $1}')
if [ "${ATTENDU}" != "${OBTENU}" ]; then
  echec "Le fichier téléchargé est incomplet ou abîmé : il n'a pas été installé. Recommencez la commande. Si cela se reproduit, prévenez votre conseiller LibPilot."
fi

# /Applications si on peut y écrire, sinon ~/Applications (compte non administrateur).
# (GROWTHLIB_INSTALL_DIR : autre dossier, pour tester sans toucher à l'app installée.)
DOSSIER_SYSTEME=/Applications
CIBLE_DOSSIER=${GROWTHLIB_INSTALL_DIR:-${DOSSIER_SYSTEME}}
if [ ! -w "${CIBLE_DOSSIER}" ]; then CIBLE_DOSSIER="${HOME}/Applications"; mkdir -p "${CIBLE_DOSSIER}"; fi
CIBLE="${CIBLE_DOSSIER}/${NOM_APP}"

# ── Ancienne application « Growth'Lib » (versions 0.1.x) ────────────────────────────────────────────────────────────────
# Un Mac qui l'a encore en aurait deux. On la retire, avec ces garde-fous :
#  - seulement si elle EXISTE, à un emplacement précis (jamais de recherche large, jamais de joker) ;
#  - seulement si c'est bien une application (dossier .app avec Contents/Info.plist, pas un lien) ;
#  - elle est FERMÉE d'abord ; si elle ne se ferme pas, on s'arrête (jamais de fermeture de force) ;
#  - on ne supprime QUE ce dossier .app : jamais le dossier de données (réglages, comptes, profils), ni autre chose ;
#  - au moindre doute, message clair et arrêt : LibPilot n'est alors pas installé et rien d'autre n'a été modifié.
# (GROWTHLIB_ATTENTE_FERMETURE : secondes d'attente de la fermeture, 30 par défaut ; ne sert qu'aux tests.)
ANCIENNE_APP="Growth'Lib.app"
ATTENTE_FERMETURE=${GROWTHLIB_ATTENTE_FERMETURE:-30}

ancienne_en_cours() { pgrep -f -- "$1/Contents/" >/dev/null 2>&1; }

retirer_ancienne() {
  chemin="$1"
  # Absente : rien à faire.
  if [ ! -e "${chemin}" ] && [ ! -L "${chemin}" ]; then return 0; fi
  case "${chemin}" in
    */"${ANCIENNE_APP}") ;;
    *) echec "Chemin inattendu pour l'ancienne application. Rien n'a été installé ni supprimé. Prévenez votre conseiller LibPilot." ;;
  esac
  case "${chemin}" in
    *\"*|*\\*|*\`*|*\$*|*\(*|*\)*|*\[*|*\]*|*\{*|*\}*|*\**|*\?*|*\|*|*\^*|*+*)
      echec "L'ancienne application « Growth'Lib » se trouve dans un dossier au nom inhabituel (${chemin}). Elle n'a pas été supprimée et LibPilot n'a pas été installé. Retirez-la à la main (glissez-la dans la Corbeille), puis recommencez la commande." ;;
  esac
  if [ -L "${chemin}" ] || [ ! -d "${chemin}" ] || [ ! -f "${chemin}/Contents/Info.plist" ]; then
    echec "« ${chemin} » ne ressemble pas à l'application « Growth'Lib ». Elle n'a pas été supprimée et LibPilot n'a pas été installé. Prévenez votre conseiller LibPilot."
  fi
  if ancienne_en_cours "${chemin}"; then
    echo "→ Fermeture de « Growth'Lib » en cours d'exécution…"
    osascript -e "tell application \"${chemin}\" to quit" >/dev/null 2>&1 || true
    i=0; while ancienne_en_cours "${chemin}" && [ "${i}" -lt "${ATTENTE_FERMETURE}" ]; do sleep 1; i=$((i + 1)); done
    if ancienne_en_cours "${chemin}"; then
      echec "L'ancienne application « Growth'Lib » est ouverte et ne se ferme pas. Fermez-la (menu « Growth'Lib », puis « Quitter »), puis recommencez la commande. Rien n'a été installé ni supprimé."
    fi
  fi
  rm -rf "${chemin}" 2>/dev/null || true
  if [ -e "${chemin}" ] || [ -L "${chemin}" ]; then
    echec "Impossible de retirer l'ancienne application « Growth'Lib » (${chemin}). Glissez-la dans la Corbeille, puis recommencez la commande. LibPilot n'a pas été installé."
  fi
  echo "→ Ancienne application « Growth'Lib » retirée. Vos données sont conservées."
}

# En mode essai (GROWTHLIB_INSTALL_DIR), seul ce dossier est regardé : l'app réellement installée n'est jamais touchée.
retirer_ancienne "${CIBLE_DOSSIER}/${ANCIENNE_APP}"
if [ -z "${GROWTHLIB_INSTALL_DIR:-}" ]; then
  retirer_ancienne "${HOME}/Applications/${ANCIENNE_APP}"
  retirer_ancienne "${DOSSIER_SYSTEME}/${ANCIENNE_APP}"
fi

if [ -z "${GROWTHLIB_INSTALL_DIR:-}" ] && pgrep -x "LibPilot" >/dev/null 2>&1; then
  echo "→ Fermeture de LibPilot en cours d'exécution…"
  osascript -e "quit app \"LibPilot\"" >/dev/null 2>&1 || true
  i=0; while pgrep -x "LibPilot" >/dev/null 2>&1 && [ ${i} -lt 30 ]; do sleep 1; i=$((i + 1)); done
fi

echo "→ Installation dans ${CIBLE_DOSSIER}…"
hdiutil attach -nobrowse -readonly -mountpoint "${TMP}/volume" "${TMP}/app.dmg" >/dev/null
SOURCE=$(find "${TMP}/volume" -maxdepth 1 -name '*.app' | head -1)
[ -n "${SOURCE}" ] || echec "Le fichier téléchargé ne contient pas l'application. Rien n'a été installé. Prévenez votre conseiller LibPilot."
rm -rf "${CIBLE}"
ditto "${SOURCE}" "${CIBLE}"
xattr -dr com.apple.quarantine "${CIBLE}" 2>/dev/null || true

if [ -n "${GROWTHLIB_INSTALL_DIR:-}" ]; then echo "✓ LibPilot ${VERSION} installé dans ${CIBLE} (test : non lancé)."; exit 0; fi
echo "✓ LibPilot ${VERSION} installé. Lancement…"
open "${CIBLE}"
