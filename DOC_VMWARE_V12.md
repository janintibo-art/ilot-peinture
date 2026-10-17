# Îlot Peinture — préparation de la VM VMware (V12)

**Statut : préproduction, à installer uniquement après validation informatique.** La V12 prépare une API centralisée et des emplacements partagés côté serveur. L'application Android V11 conserve encore sa configuration locale des zones : l'intégration Android de `/zones` est une étape ultérieure.

## Pré requis proposés (à valider par l'équipe informatique)

- VM **dédiée** Ubuntu Server 24.04 LTS ou Debian 12, jamais sur la VM de pointage.
- 2 vCPU, 4 Go RAM, 30 Go disque pour un petit pilote ; ajuster selon charge et sauvegardes.
- Docker Engine et plugin Docker Compose, réseau interne, IP réservée, pare-feu.
- HTTPS via reverse proxy interne / certificats de confiance ou accès VPN ; ne pas exposer le port HTTP à Internet. L'APK existant accepte HTTP sur LAN, mais celui-ci n'est pas recommandé pour de vraies données métier.
- Validation sécurité / confidentialité par l'administrateur avant de saisir des données de clients.

## Installation (par un administrateur)

1. Cloner le dépôt `https://github.com/janintibo-art/ilot-peinture` sur la **VM dédiée**.
2. Dans `server/`, copier `.env.example` en `.env`, puis générer un secret avec `python3 -c "import secrets; print(secrets.token_urlsafe(48))"`. Remplacer entièrement `API_TOKEN` par ce secret. Ne jamais publier ce fichier.
3. Conserver `BIND_ADDRESS=127.0.0.1` tant que le reverse proxy sécurisé n'est pas en place. Une configuration à `0.0.0.0` nécessite des règles réseau strictes et un canal TLS adapté.
4. Exécuter `docker compose up -d --build` dans `server/`, puis `docker compose ps` et `curl http://127.0.0.1:8000/health` sur la VM.
5. Dans l'APK, désactiver Démonstration, configurer l'URL réseau validée et la clé, puis tester depuis le Wi-Fi de l'entreprise.

## Sauvegardes et reprise

La base SQLite est persistée dans le volume Docker `ilot_data`. La commande de sauvegarde cohérente est `docker compose exec -T api python backup.py`. Prévoir une tâche planifiée sur la VM, la copie chiffrée **hors de la VM** des sauvegardes, la rotation, et un test documenté de restauration. Ne pas utiliser `docker compose down -v` : cela supprime le volume et les données. Les snapshots VMware ne remplacent pas une sauvegarde applicative. Les fichiers `.sqlite3` produits dans `/data/backups` restent dans le volume tant qu'ils ne sont pas exportés vers un autre emplacement sécurisé.

## Limites avant production

- Identifiants individuels, rôles, audit complet des actions, TLS, rotation de secret et stockage sécurisé sur Android restent à développer et valider.
- La V12 propose les endpoints communs `/zones` et `/locations`, **sans synchronisation de la configuration V11 sur Android**.
- Pas d'intégration à l'application de pointage ni à son serveur actuel.
- Vérifier les règles IT de votre entreprise avant d'héberger des dossiers et des données client.
