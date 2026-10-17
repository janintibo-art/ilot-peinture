# Îlot Peinture — Traçabilité V14 (pilote)

## Objectif
Relier les numéros de lots fournisseurs aux dossiers clients pour les procédés **liquide** et **poudre**.

### Peinture liquide
Identifiant produit, lot, fournisseur, référence, certificat, réception, péremption ; dossier, quantité, numéro opérateur saisi, horaire, lot durcisseur, rapport de mélange et durée de vie du mélange.

### Peinture poudre
Mêmes données matière et dossier ; température et durée de cuisson enregistrées pour chaque opération. Ces valeurs sont **déclaratives**, pas des mesures automatiquement capturées par un équipement.

### API serveur
- `GET/POST /material-lots`
- `POST /process-records`
- `GET /files/{id}/traceability`
- `GET /material-lots/{id}/traceability`

Les données existantes ne sont pas effacées : deux tables sont ajoutées au démarrage. Sauvegarder la base avant mise à jour.

## Limites et sécurité
**Cette version pilote ne prouve aucune conformité EN 9100 ou autre référentiel.** Le numéro opérateur est saisi librement et n'est pas une authentification. La clé partagée du serveur ne permet pas l'attribution fiable des actes. Les opérations sont ajoutées sans fonction de modification via cette API, mais un administrateur de la base peut les modifier : il n'y a pas encore de journal inviolable. Il manque entre autres une gestion de comptes et rôles, l'identification de pièces/lots de fabrication, la gestion des certificats réels, la validation qualité, le contrôle des dates/péremptions, la signature et des sauvegardes restaurées et éprouvées.

**Ne pas entrer de données sensibles ou de production aéronautique dans cette version pilote avant revue du service qualité et informatique.**
