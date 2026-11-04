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
- `helper.entitlements` : dictionnaire vide pour les autres helpers.

Aucune exception `disable-library-validation`, `allow-unsigned-executable-memory`
ou `get-task-allow`. Chaque bibliothèque, framework, helper et app est signé
séparément avec horodatage. Les exécutables utilisent le Hardened Runtime.
Les symboles `.dSYM` sont conservés à côté du livrable, hors de l’application.

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
