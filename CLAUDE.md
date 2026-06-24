# CLAUDE.md — Instructions pour Claude Code

> Ce fichier est lu automatiquement par Claude Code à chaque session.
> Il sert de pont vers les fichiers `.agents/` qui contiennent les règles du projet.

---

## Lecture obligatoire en début de session

**Avant toute action, lis ces fichiers dans cet ordre :**

1. [.agents/AGENT.md](.agents/AGENT.md) — comportement général, standards, checklist de livraison
2. [.agents/CONVENTIONS.md](.agents/CONVENTIONS.md) — stack technique, nommage, règles spécifiques au projet
3. [.agents/CHANGELOG_AGENT.md](.agents/CHANGELOG_AGENT.md) — état actuel du code, ce qui a déjà été fait
4. [.agents/DECISIONS.md](.agents/DECISIONS.md) — décisions techniques structurantes déjà prises

Ces fichiers sont la mémoire du projet. Les ignorer entraîne des incohérences avec le travail déjà livré.

---

## Documentation obligatoire en fin de ticket

Après chaque ticket ou tâche significative, tu **dois** mettre à jour :

### `.agents/CHANGELOG_AGENT.md`
- Section "État global" : met à jour le statut du module concerné
- Nouvelle entrée en bas avec : fichiers créés/modifiés, ce qui est utilisable, hypothèses posées, dette éventuelle

### `.agents/DECISIONS.md`
- Ajoute une entrée pour chaque choix technique structurant (format de donnée, pattern d'auth, contournement d'une lib, etc.)
- Format : Contexte / Décision / Alternative écartée / Conséquences

**Ne considère pas un ticket terminé tant que ces deux fichiers ne sont pas à jour.**

---

## Stack technique (rappel)

Kubernetes · Ingress NGINX · cert-manager (Cloudflare DNS01) · CouchDB 3 (StatefulSet) · Rust / Axum (backend) · React / Vite (frontends) · GitHub Container Registry (ghcr.io)

---

## Règles rapides

- Nommage des ressources : `neon-beat-{env}-{composant}` (ex : `neon-beat-prod-back`)
- Labels obligatoires sur chaque ressource : `app.kubernetes.io/name`, `app.kubernetes.io/part-of: neon-beat`, `app.kubernetes.io/instance`
- `namespace` explicite sur chaque ressource — ne jamais laisser implicite
- Jamais de `Secret` avec des valeurs réelles dans le dépôt — uniquement des `.example.yml`
- `replicas: 1` sur le backend tant que l'état temps réel n'est pas externalisé (Redis/NATS)
- Toujours définir `readinessProbe`, `livenessProbe`, `resources.requests` et `resources.limits`
- Maintenir la parité prod / preprod (même structure, ressources réduites en preprod)
- Commits : `[ADD]` nouveau · `[IMP]` amélioration · `[REF]` refacto · `[FIX]` bug
