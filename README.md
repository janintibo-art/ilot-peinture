# Îlot Peinture — V2 (Linux / NAS + Android)

Cette mise à jour conserve les fonctions V1 (produits, mouvements, recherche de dossiers) et ajoute des historiques consultables ainsi qu’une configuration serveur sans clé par défaut.

## Déploiement initial sur le serveur Linux / NAS

Le serveur doit disposer de Docker et de `docker compose`, être connecté au réseau privé de l'entreprise et idéalement avoir une adresse IP LAN réservée.

1. Copier le dossier `server` du dépôt sur le Linux/NAS (par ex. `/opt/ilot-peinture/server`).
2. Dans ce dossier, copier `.env.example` vers `.env`.
3. Générer une clé aléatoire longue avec `python3 -c "import secrets; print(secrets.token_urlsafe(48))"` et la coller dans `.env` à la place de l'exemple. **Ne pas partager cette clé publiquement.**
4. Démarrer `docker compose up -d --build` dans le dossier `server`.
5. Vérifier `http://IP_SERVEUR:8000/health` sur le réseau privé (réponse JSON `status: ok`).
6. Sur chaque Android, ouvrir Réglages, saisir `http://IP_SERVEUR:8000` et la même clé.

**NAS** : fonctionne uniquement si Docker/Container Manager et Docker Compose sont compatibles avec le NAS ; sinon héberger le serveur sur une machine Linux du réseau.

## Mise à jour d'un serveur V1

Sauvegarder la base avant de redéployer. Préparer `.env` et redémarrer avec `docker compose up -d --build`. La table `file_history` est créée automatiquement au démarrage et les données existantes restent dans le volume `ilot_data` tant que ce volume n'est pas supprimé. Ne jamais lancer `docker compose down -v` sans sauvegarde.

## Historique

- Chaque changement d'emplacement ou de statut d'un dossier est horodaté dans `file_history`.
- Historique stock des produits, y compris le stock initial des **nouveaux** produits V2. Les stocks initiaux enregistrés sous V1 ne peuvent pas être reconstitués rétroactivement.
- Les écrans d'historique affichent les 150 dernières entrées par objet.

## Sécurité importante

- `server/.env` est ignoré par Git ; aucune clé n'est contenue dans le dépôt.
- Le serveur refuse de démarrer avec une clé absente ou trop courte.
- Port 8000 **uniquement sur le réseau interne protégé** : firewall, pas de redirection Internet. Pour un accès externe, prévoir HTTPS, VPN et comptes utilisateurs.
- La clé est pour le moment **commune à tous les Android** et sauvegardée dans les préférences locales. Ce n'est pas encore une solution prête à traiter des données sensibles en environnement de production. Prochaine étape : comptes individuels / rôles et stockage sécurisé des identifiants.
- Prévoir des sauvegardes automatiques du volume Docker `ilot_data` et tester régulièrement une restauration. SQLite est adapté à une petite équipe sur une seule instance serveur ; pour une forte concurrence, envisager PostgreSQL.
- Ne pas remplacer une sauvegarde SQL par une simple copie du fichier `.db` pendant les écritures en WAL. Utiliser l'API de sauvegarde SQLite ou arrêter proprement le service.

## APK Android

GitHub Actions, workflow **Build APK Android** ; artifact `ilot-peinture-v2-apk` après build réussi. Installation manuelle sur chaque appareil. Le HTTP Android est autorisé pour le LAN privé ; éviter les réseaux non maîtrisés.


## Site vitrine GitHub Pages (V4)

Le site public est dans `site/index.html`. Chaque workflow réussi copie l'APK dans `downloads/ilot-peinture.apk`, met à jour le numéro de build et publie le site avec `actions/deploy-pages`. Lien prévu : https://janintibo-art.github.io/ilot-peinture/ (actif uniquement après configuration et premier déploiement vert).

**Activation une seule fois** : sur GitHub, dépôt → Settings → Pages → Build and deployment → Source : **GitHub Actions**. Sur un dépôt privé, l'accès GitHub Pages dépend du plan/visibilité et de la politique de l'organisation. Pour permettre un accès sans compte GitHub, vérifier que le site est effectivement public. Ne jamais placer les clés, les URL serveur privées ni les données clients dans les fichiers du site ou dans un dépôt public.

En cas d'échec de `flutter test` ou du build Android, la publication est interrompue et le dernier APK publié est conservé. **Chaque nouveau build vert** met à jour l'APK du site : les collègues doivent télécharger de nouveau la dernière version pour la tester.


## V13 — guide VMware et numéro professionnel

Le site GitHub Pages publie le guide `DOC_VMWARE_V12.md` en téléchargement et sa lecture dans `guide-vmware.html`. Dans les réglages Android, chaque personne peut enregistrer son numéro professionnel (exemple : 128). **Ce numéro est conservé localement sur le téléphone : il ne constitue pas un login, ne sécurise pas les accès et n’est pas encore lié à l’audit serveur.** La création de vrais comptes, des permissions, d’une preuve d’identité et de l’audit nominatif est à réaliser avant usage en production.
