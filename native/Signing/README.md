# Signature macOS d’Arc Reborn

Le script `../scripts/sign-and-notarize.sh` adapte le workflow du skill
`macos-spm-app-packaging` au bundle natif AppKit/CEF. Il utilise le build existant,
sans reconstruire ni remplacer le moteur Chromium personnalisé, et travaille
sur une copie. Le profil utilisateur reste hors du bundle.

## Certificat et autorisations

Utiliser un certificat **Developer ID Application** du trousseau, avec sa clé
privée. L’équipe attendue est `LWSP9A5UDA` (surcharge : `BROWSER_SIGN_TEAM`).
`BROWSER_SIGN_IDENTITY` permet de choisir explicitement l’empreinte du certificat.
Les clés privées et identifiants de notarisation ne doivent jamais être ajoutés
au dépôt ou au bundle.

Les entitlements suivent Chromium **156.0.8078.80** :

- `app.entitlements` : capacités du processus navigateur ; les consentements
  macOS et les autorisations des sites continuent de s’appliquer.
- `jit.entitlements` : V8/JIT pour les helpers Renderer et GPU uniquement.
- Le processus dédié `Arc Reborn Helper (CDM)` utilise `cdm.entitlements` et `cdm-library.coderequirement` ensemble. À partir de macOS 14, il peut charger le module `libwidevinecdm` signé en Developer ID par Google (`EQHXZ8M8AV`). La règle autorise aussi les bibliothèques de l’équipe qui signe Arc Reborn. Le navigateur dirige uniquement le service Chromium `media.mojom.CdmServiceBroker` sous sandbox `cdm` vers cet exécutable.
- Les autres helpers utilisent le dictionnaire vide `helper.entitlements`.

L’exception de chargement de bibliothèque tierce est propre au processus CDM.
macOS applique la contrainte de bibliothèque depuis Sonoma. Sur Ventura,
Arc Reborn conserve le chemin CEF standard et le helper dédié refuse de démarrer.
Chaque bibliothèque, framework, helper et app est signé
séparément avec horodatage. Les exécutables utilisent le Hardened Runtime.
Les symboles `.dSYM` sont conservés à côté du livrable, hors de l’application.

Pour contrôler le résultat, exécuter le test `widevine` sur la copie signée
avec le Hardened Runtime. La signature du composant Google est indépendante
des signatures d’hôte VMP éventuellement exigées par un fournisseur de contenus.
[Contraintes de chargement Apple](https://developer.apple.com/videos/play/wwdc2023/10266/)
et [vérifications d’hôte de CEF](https://github.com/chromiumembedded/cef/blob/cf671c072925b27823a61181152f4f288e8e4306/libcef/common/cdm_host_file_path.cc).

Dans un nouveau profil, saisir `arc://components` dans la barre d’adresse.
Si *Widevine Content Decryption Module* n’a pas encore de version installée,
demander la mise à jour du composant, puis recharger le lecteur. Le scénario
automatisé demande une licence temporaire pour le film de démonstration *Angel One*
et vérifie que la lecture avance avec une clé utilisable et des images décodées.
[Procédure de test](../../docs/development/engine.md#widevine-on-macos).

Références : [CEF](https://chromiumembedded.github.io/cef/code_signing.html),
[Chromium app](https://github.com/chromium/chromium/blob/156.0.8078.80/chrome/app/app-entitlements.plist),
[Renderer](https://github.com/chromium/chromium/blob/156.0.8078.80/chrome/app/helper-renderer-entitlements.plist),
[GPU](https://github.com/chromium/chromium/blob/156.0.8078.80/chrome/app/helper-gpu-entitlements.plist).

## Préparer et vérifier

Depuis la racine du projet :

```bash
native/scripts/sign-and-notarize.sh sign native/build/Browser.app \
  'native/build/distribution/Arc Reborn.app'
```

La destination doit être absente. Vérifier le démarrage de cette copie dans un
profil isolé avant la soumission. Les compilations locales préfèrent désormais
le certificat Developer ID disponible ; cela ne remplace pas ce workflow de
distribution, qui active le Hardened Runtime et demande la notarisation.

## Clés d’accès de Mots de passe

Le parcours « Utiliser un téléphone ou une tablette » utilise le Bluetooth pour
vérifier la proximité. Son texte de consentement figure dans le paquet en
français et en anglais. Ce parcours fonctionne avec le moteur de production.

Pour proposer directement les clés de Mots de passe sur le Mac, le titulaire du
compte d’organisation doit demander la capacité pour l’identifiant explicite
`local.browser.native`. Après accord, créer un profil **Developer ID** pour cet
identifiant, cette capacité et le certificat de distribution. [Demande Apple](https://developer.apple.com/contact/request/macos-browsers-passkeys/) · [Documentation Apple](https://developer.apple.com/documentation/authenticationservices/passkey-use-in-web-browsers)

Placer le fichier `.provisionprofile` hors du dépôt. Depuis la racine du projet,
utiliser les commandes suivantes pour préparer une copie signée.

```bash
export BROWSER_PASSKEY_PROFILE="/chemin/privé/ArcReborn.provisionprofile"
BROWSER_RELEASE_BUILD=1 native/scripts/build.sh
native/scripts/sign-and-notarize.sh sign 'native/build/Arc Reborn.app' \
  'native/build/distribution-avec-cles/Arc Reborn.app'
```

Cette configuration sélectionne le moteur décrit par `Engine/passkeys.lock.json`.
Il ancre la présentation système à la fenêtre AppKit de l’onglet. Les contrôles
de signature vérifient le profil, le certificat et le moteur, puis relisent les
droits de l’application signée. Les helpers conservent leur propre signature.
Pour compiler ou tester le moteur seul, définir `BROWSER_PASSKEY_ENGINE=1`
avec les commandes habituelles de compilation du moteur. Pour une CI neuve,
mettre l’archive vérifiée à l’emplacement indiqué par ce verrou avant d’activer
le secret de distribution `APPLE_PASSKEY_PROFILE` (profil encodé en base64).

Pour la recette, utiliser un compte de test qui a déjà une clé dans Mots de passe.
Sur le site qui a créé cette clé, choisir Mots de passe et valider avec Touch ID.
Vérifier que le site ouvre la session. Depuis les réglages de sécurité du compte,
créer une seconde clé, vérifier sa présence dans Mots de passe, puis ouvrir une
nouvelle session avec cette clé. Le QR code téléphone suit un autre parcours.

## Soumettre à Apple

Configurer soit `BROWSER_NOTARY_KEYCHAIN_PROFILE`, soit `BROWSER_NOTARY_KEY`
(chemin privé du `.p8`), `BROWSER_NOTARY_KEY_ID` et `BROWSER_NOTARY_ISSUER`
(uniquement pour une clé d’équipe). Ces variables ne contiennent aucun secret
à enregistrer dans le projet.

```bash
native/scripts/sign-and-notarize.sh submit 'native/build/distribution/Arc Reborn.app'
```

Le fichier `Arc Reborn-submission.json` contient l’identifiant de soumission.
Suivre l’état avec `xcrun notarytool info` et les mêmes options d’authentification.
En cas de refus, récupérer `notarytool log` et corriger avant de distribuer.

Après le statut **Accepted** :

```bash
native/scripts/sign-and-notarize.sh staple 'native/build/distribution/Arc Reborn.app'
```

Cette dernière étape attache le ticket Apple, vérifie Gatekeeper et produit le
ZIP de distribution avec son SHA-256. Elle ne publie rien et ne remplace pas
l’app en cours d’utilisation.
