# Îlot Peinture — v1

Application Android Flutter + serveur FastAPI pour gérer les produits de peinture et retrouver les dossiers dans l'atelier.

## Fonctionnalités
- Gestion des peintures liquides / poudres, solvants, autres consommables.
- Quantités, unités, seuils d'alerte, emplacement, mouvements d'entrée/sortie horodatés côté serveur.
- Dossiers avec numéro unique, client, emplacement précis, statut et observations.
- Recherche de dossier par client, référence et emplacement.
- Synchronisation par API partagée : plusieurs Android sur le même réseau utilisent les mêmes données.
- Tableau de bord, interface mobile, connexion configurable au serveur.

## Installation serveur
Sur un PC/serveur **allumé en permanence** avec Docker installé :

```bash
cd server
```

Éditer `docker-compose.yml` et remplacer impérativement la valeur `CHANGEZ_CETTE_CLE_AVANT_UTILISATION` par une clé longue et aléatoire, puis :

```bash
docker compose up -d --build
```

Serveur disponible sur `http://ADRESSE_IP_DU_SERVEUR:8000` sur le LAN. Réserver une IP locale fixe dans votre routeur. Dans les réglages Android, saisir cette URL et la clé définie dans Docker.

## Android
Un push sur `main` exécute GitHub Actions > **Build APK Android**. L'APK est dans **Artifacts**, rubrique `ilot-peinture-v1-apk`. Le workflow génère le projet Android Flutter et autorise le HTTP pour un **réseau local privé** uniquement.

## Sécurité et limites de la v1
- Prototype d'atelier : une clé partagée entre appareils, sans comptes personnels ni rôles. Ne pas exposer le port 8000 à Internet.
- Utiliser un réseau Wi-Fi d'entreprise protégé, idéalement un VLAN et HTTPS via reverse proxy. Aucun secret ne doit être commité dans GitHub ; définir le secret localement au serveur.
- Faire une sauvegarde quotidienne du volume `ilot_data`, tester la restauration.
- Mouvements conservés dans la base, mais pas encore d'écran historique ou d'inventaire d'audit.
- Pas encore de gestion des lots, DLU, FDS, pictogrammes CLP, habilitations, commandes fournisseurs, alertes push, photos, lecteurs code-barres ni mode hors ligne.
- Le comptage des dossiers affiche les 300 derniers résultats dans cette version ; une pagination serveur sera nécessaire au-delà.

## Architecture
`lib/main.dart` : appli Flutter. `server/main.py` : API FastAPI/SQLite. `server/docker-compose.yml` : hébergement et stockage persistant. `.github/workflows/build-apk.yml` : APK CI.
