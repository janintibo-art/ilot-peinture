# Îlot Peinture V21 — comptes professionnels (pilote)

**Attention : V21 n'est PAS une traçabilité d'audit EN 9100.** Elle apporte une première API de comptes individuels, mais les endpoints historiques `/products`, `/files`, `/material-lots`, `/process-records` utilisent encore la clé API commune. Un numéro de salarié saisi dans une opération n'est donc pas vérifié contre sa session. Le branchement des opérations à l'identité serveur est à réaliser avant toute utilisation réelle.

## Sécurité et administration

- Déploiement exclusivement dans une VM VMware dédiée, après validation informatique, sur un réseau interne protégé avec **HTTPS** (proxy/TLS), pas d'accès Internet direct.
- Sauvegarder et tester une restauration SQLite avant installation. Conserver `API_TOKEN` confidentiel. Ne pas publier `.env` ni la base sur GitHub.
- Docker : `docker compose up -d --build` puis, depuis la VM, initialiser le premier administrateur avec `docker compose exec -it api python bootstrap_account.py` (commande interactive une seule fois). Ne pas créer de véritable compte avant validation SSI.
- Les mots de passe sont dérivés avec PBKDF2-HMAC-SHA256 et sel aléatoire ; les sessions durent 8 heures et sont stockées sous forme de hachage.
- API pilote : `POST /auth/login` avec `employee_number` et `password`, `GET /auth/me`, `POST /auth/logout`, `POST /auth/users` (administrateur connecté), `GET /auth/events` (qualité/administrateur). Ne jamais enregistrer le jeton en clair dans un fichier ou un dépôt public.
- Cette première version ne propose ni écran Android de connexion, ni limitation centralisée des tentatives, ni changement de mot de passe/révocation globale, ni attribution sécurisée des modifications métier. Ces points sont **bloquants pour la production**.
- Les événements d'identification sont stockés en SQLite et ne constituent pas encore un journal inviolable. Pour l'audit, prévoir journal externe protégé, comptes et rôles validés par le service qualité, horloge fiable, contrôles de signature, gestion des corrections, sauvegardes régulières testées.
