# DECISIONS.md — Décisions techniques structurantes

## D001 — Séparation domaine API / frontends

**Contexte :** Le backend expose `/admin/**` pour les routes API admin. Les frontends sont
servis sous `/admin/` pour l'interface graphique admin. Un seul domaine crée un conflit
de routage Ingress impossible à résoudre sans modifier le code backend.

**Décision :** Deux domaines distincts :
- `api.neon-beat.example.com` → backend Rust (toutes routes API, SSE, WebSocket)
- `neon-beat.example.com` → frontends (`/admin`, `/buzzer`, `/`)

**Alternative écartée :** Préfixe `/api/*` pour le backend — rejeté car le backend
expose `/admin/**`, `/public/**`, `/sse/*`, `/ws` sans préfixe configurable.

**Conséquences :** Les frontends doivent configurer `VITE_API_BASE_URL` vers le domaine
API. Les deux TLS sont gérés via cert-manager.

---

## D002 — CouchDB en StatefulSet (pas Deployment)

**Contexte :** CouchDB est stateful — les données sont écrites sur disque.

**Décision :** Utiliser un `StatefulSet` avec `volumeClaimTemplates` pour garantir une
identité de pod stable et un PVC dédié par instance.

**Alternative écartée :** `Deployment` + PVC externe attaché manuellement — moins
idiomatique, identité de pod instable, problèmes de réattachement en cas de reschedule.

**Conséquences :** CouchDB a un nom DNS stable (`neon-beat-prod-couchdb-0.neon-beat-prod-couchdb`).
Le scaling horizontal CouchDB nécessite une configuration cluster CouchDB spécifique (hors scope TP).

---

## D003 — 1 replica backend jusqu'à externalisation de l'état temps réel

**Contexte :** Le backend Rust conserve l'état de partie en mémoire (phase, scores,
connexions SSE/WS). Plusieurs replicas divergeraient sans bus d'événements partagé.

**Décision :** `replicas: 1` pour le backend en prod et preprod. Ce choix est documenté
dans les fichiers deployment.yml (commentaire inline).

**Alternative écartée :** Plusieurs replicas avec sticky sessions — ne résout pas tous
les cas de désynchronisation inter-pods (ex : admin sur pod A, joueur sur pod B).

**Conséquences :** Pas de haute disponibilité sur le backend. Une coupure entraîne une
interruption de partie. La prochaine étape est d'intégrer Redis Pub/Sub ou NATS avant
d'augmenter le nombre de replicas.

---

## D004 — Cloudflare DNS01 pour cert-manager (migration depuis Infomaniak)

**Contexte :** Le DNS a été migré de Infomaniak vers Cloudflare.

**Décision :** Utiliser `cluster-issuer-cloudflare.yml` (DNS01 via Cloudflare) en
production. Le fichier `cluster-issuer.yml` (webhook Infomaniak) est conservé pour
référence historique mais n'est plus actif.

**Alternative écartée :** HTTP01 — ne permet pas les certificats wildcard et requiert
une exposition publique de l'Ingress sur le port 80 pendant la validation.

**Conséquences :** Le Secret `cloudflare-api-token` doit être créé dans le namespace
`cert-manager` avant d'appliquer les ClusterIssuers.

---

## D005 — imagePullPolicy différenciée backend vs CouchDB

**Contexte :** Le backend est mis à jour fréquemment via CI/CD avec des tags re-utilisés
(`:prod`, `:preprod`). CouchDB utilise une image officielle avec version fixe.

**Décision :**
- Backend et frontends : `imagePullPolicy: Always`
- CouchDB : `imagePullPolicy: IfNotPresent`

**Conséquences :** Le déploiement backend force un pull à chaque redémarrage de pod,
ce qui requiert une connexion registry fonctionnelle. Utiliser des `imagePullSecrets`
si le registry GHCR est privé.

---

## D006 — HPA uniquement sur les frontends (pas le backend)

**Contexte :** L'autoscaling horizontal du backend est bloqué par la contrainte D003
(état temps réel en mémoire). Les frontends sont stateless et scalables librement.

**Décision :** HPA sur les 3 frontends (CPU threshold 70%), backend exclu du HPA.
- Game front : 2–10 replicas
- Admin front : 2–5 replicas (usage plus limité)
- Buzzer front : 2–10 replicas

**Conséquences :** Le backend reste le point de contention unique. Si le CPU backend
devient le goulot d'étranglement, l'intégration d'un event bus (Redis/NATS) est
le prérequis avant tout scaling.

---

## D007 — NetworkPolicy default-deny dans le namespace prod

**Contexte :** Sans NetworkPolicy, tous les pods peuvent communiquer entre eux dans
le cluster, ce qui est contraire au principe de moindre privilège.

**Décision :** Politique default-deny sur tout le namespace `neon-beat`, avec des
règles d'autorisation explicites :
- Ingress NGINX → tous les pods (trafic entrant public)
- Backend → CouchDB (port 5984 uniquement)
- kube-dns → tous les pods (résolution DNS)

**Conséquences :** Tout nouveau composant doit avoir une NetworkPolicy explicite avant
de pouvoir communiquer avec les autres pods.
