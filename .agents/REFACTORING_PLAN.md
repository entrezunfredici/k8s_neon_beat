# Plan de refactoring — Découpage SRP + DRY

> Propose un découpage cohérent pour chaque microservice, avec diagrammes de classes
> et de fichiers. Utilise la composition en priorité, l'héritage uniquement quand
> une relation "est-un" est justifiée.

---

## Vue d'ensemble

Le projet présente deux types de violations :

1. **God objects** : un module/fichier cumule orchestration, état, persistance, réseau
   et logique métier (surtout backend Rust et contextes React).
2. **Duplication silencieuse** : la gestion SSE, le parsing JSON, la gestion d'erreur
   HTTP sont réécrits dans chaque service/hook sans abstraction partagée.

Principe directeur : **composition over inheritance**. Dans ce projet TypeScript/React
et Rust, l'héritage de classe est rare et souvent anti-pattern. On préfère :
- des hooks qui composent d'autres hooks (React)
- des traits + implémentations concrètes (Rust)
- des fonctions utilitaires pures partagées (DRY)

---

## 1. Backend Rust — `neon-beat-back`

### 1.1 État actuel (God modules)

```mermaid
classDiagram
  class AppState {
    +game: Option~Game~
    +teams: Vec~Team~
    +phase: GamePhase
    +sse_clients: Vec~SseSender~
    +persist_debounce: Timer
    +load_from_db()
    +save_to_db()
    +broadcast_sse()
    +debounce_persist()
    +transition_phase()
    +register_sse_client()
    +remove_sse_client()
  }

  class AdminService {
    +create_game()
    +load_game()
    +start_game()
    +pause_game()
    +next_question()
    +validate_answer()
    +compute_scores()
    +broadcast_phase_changed()
    +persist_state()
    +reset_game()
  }

  class WebSocketService {
    +handle_connection()
    +handle_buzz()
    +handle_pairing()
    +send_phase_to_buzzer()
    +transition_to_pause()
    +register_buzzer()
  }

  AppState <.. AdminService : utilise
  AppState <.. WebSocketService : utilise
```

### 1.2 Découpage proposé

```mermaid
classDiagram
  direction TB

  class SseHub {
    -clients: Vec~SseSender~
    +register(sender)
    +unregister(sender)
    +broadcast(event: SseEvent)
    +broadcast_to_admin(event)
    +broadcast_to_public(event)
  }

  class PersistenceCoordinator {
    -db: CouchDbStore
    -debounce_handle: Option~JoinHandle~
    +schedule_save(state: GameSnapshot)
    +force_save(state: GameSnapshot)
    +load() GameSnapshot
  }

  class AppState {
    +game: Option~Game~
    +teams: Vec~Team~
    +phase: GamePhase
    +sse_hub: Arc~SseHub~
    +persistence: Arc~PersistenceCoordinator~
  }

  class PhaseTransitionService {
    +can_transition(from, to) bool
    +apply(state, transition) Result
    +build_phase_event(phase, ctx) SseEvent
  }

  class GameLifecycleService {
    +create(payload) Game
    +load(id) Game
    +reset(state)
    +delete(id)
  }

  class BroadcastService {
    +phase_changed(hub, phase, ctx)
    +score_adjustment(hub, team, delta)
    +answers_found(hub, ids)
    +hints_revealed(hub, ids)
  }

  class PairingService {
    +assign_buzzer(team_id, buzzer_id, state)
    +unassign_buzzer(buzzer_id, state)
    +find_team_by_buzzer(id, state) Option~Team~
  }

  class WebSocketHandler {
    +accept(socket, state)
    +handle_message(msg, state)
    +on_disconnect(buzzer_id, state)
  }

  AppState *-- SseHub : composition
  AppState *-- PersistenceCoordinator : composition
  PhaseTransitionService ..> AppState : lit/modifie
  GameLifecycleService ..> AppState : lit/modifie
  BroadcastService ..> SseHub : utilise
  WebSocketHandler ..> PairingService : délègue
  WebSocketHandler ..> PhaseTransitionService : délègue
  WebSocketHandler ..> BroadcastService : délègue
```

### 1.3 Structure de fichiers proposée

```
src/
├── state/
│   ├── mod.rs              — AppState (struct + new())
│   ├── sse_hub.rs          — SseHub : register / broadcast
│   └── persistence.rs      — PersistenceCoordinator : debounce + save/load
│
├── services/
│   ├── phase_transition.rs — Transitions d'état machine (pure logic)
│   ├── game_lifecycle.rs   — CRUD jeux (create/load/reset/delete)
│   ├── broadcast.rs        — Construction + envoi d'événements SSE
│   ├── pairing.rs          — Logique buzzer-équipe
│   └── websocket.rs        — Handler WebSocket (accept + dispatch)
│
├── routes/
│   ├── admin.rs            — Routing HTTP uniquement (pas de logique métier)
│   └── public.rs
│
└── domain/
    ├── game.rs             — structs Game, Team, Question, Answer
    ├── phase.rs            — enum GamePhase + StateMachine
    └── events.rs           — structs SseEvent, WsMessage (types purs)
```

### 1.4 Trait partagé pour les services (héritage via trait Rust)

```mermaid
classDiagram
  class GameEventPublisher {
    <<trait>>
    +publish(event: SseEvent)*
  }

  class BroadcastService {
    +publish(event: SseEvent)
  }

  class NoopPublisher {
    +publish(event: SseEvent)
  }

  GameEventPublisher <|.. BroadcastService : implémente
  GameEventPublisher <|.. NoopPublisher : implémente (tests)

  PhaseTransitionService ..> GameEventPublisher : dépend (injection)
  GameLifecycleService ..> GameEventPublisher : dépend (injection)
```

`PhaseTransitionService` et `GameLifecycleService` dépendent du trait
`GameEventPublisher`, pas de l'implémentation concrète. En tests, on injecte
`NoopPublisher` sans avoir besoin d'un vrai SSE.

---

## 2. Admin Front — `neon-beat-admin-front`

### 2.1 État actuel — Contextes surchargés

```mermaid
classDiagram
  class ApiContext {
    +sse: EventSource
    +token: string
    +getGames()
    +getGame()
    +postGame()
    +getTeams()
    +postTeam()
    +postScore()
    +postAnswerFound()
    +getCurrentPhase()
    +isServerReady: bool
    +handleSseError()
    +extractToken()
  }

  class GameManagementContext {
    +games + teams + question
    +gameState + answersFound
    +loadGames() + loadTeams()
    +createGame() + importQuestionsSequence()
    +markAnswerFound() + grantTeamPoints()
    +canStartGame() + canPauseGame()
    +onPhaseChanged() + onPairingAssigned()
    +resetWholeGame()
  }

  GameManagementContext ..> ApiContext : consomme
```

### 2.2 Découpage proposé — Contextes

```mermaid
classDiagram
  direction TB

  class ApiClient {
    <<service>>
    +get~T~(path) Promise~T~
    +post~T~(path, body) Promise~T~
    +patch~T~(path, body) Promise~T~
    +delete(path) Promise~void~
    +handleError(err) ApiError
  }

  class SseManager {
    <<service>>
    +connection: EventSource
    +isReady: bool
    +on(event, handler)
    +off(event, handler)
    +reconnect()
  }

  class ApiContext {
    <<context>>
    +client: ApiClient
    +sse: SseManager
    +isServerReady: bool
    +token: string
    [expose toutes les fonctions API typées]
  }

  class GameLifecycleContext {
    <<context>>
    +game + gameState
    +createGame() + loadGame() + resetGame()
    +startGame() + pauseGame() + nextQuestion()
    +canStartGame() + canPauseGame()
  }

  class TeamContext {
    <<context>>
    +teams + currentTeamPairing
    +loadTeams() + createTeam() + grantPoints()
    +canPairTeams() + canDeleteTeam()
  }

  class QuestionContext {
    <<context>>
    +question + answersFound + hintsFound
    +markAnswerFound() + resetFoundAnswers()
  }

  class SseDispatchContext {
    <<context>>
    [s'abonne au SseManager]
    [dispatche chaque event vers le bon contexte]
    -onPhaseChanged → GameLifecycleContext
    -onPairingAssigned → TeamContext
    -onAnswersFound → QuestionContext
  }

  ApiContext *-- ApiClient : composition
  ApiContext *-- SseManager : composition
  GameLifecycleContext ..> ApiContext : lit
  TeamContext ..> ApiContext : lit
  QuestionContext ..> ApiContext : lit
  SseDispatchContext ..> SseManager : s'abonne
  SseDispatchContext ..> GameLifecycleContext : notifie
  SseDispatchContext ..> TeamContext : notifie
  SseDispatchContext ..> QuestionContext : notifie
```

### 2.3 Structure de fichiers proposée

```
src/
├── services/
│   ├── ApiClient.ts          — fetch wrapper + gestion erreurs HTTP
│   └── SseManager.ts         — EventSource + reconnexion + on/off
│
├── Context/
│   ├── ApiContext.tsx         — compose ApiClient + SseManager, expose hooks API
│   ├── GameLifecycleContext.tsx — état jeu + transitions + guards canXxx
│   ├── TeamContext.tsx         — équipes + pairing + scores
│   ├── QuestionContext.tsx     — question active + réponses + indices
│   └── SseDispatchContext.tsx  — routing des events SSE vers les contextes métier
│
├── hooks/
│   ├── useGameController.ts   — extraite de GameController.tsx
│   ├── useGameCreationForm.ts — extraite de GameCreator.tsx
│   └── useSongController.ts   — extraite de SongController.tsx
│
├── utils/
│   ├── parseSseEvent.ts       — JSON.parse + try/catch (DRY, partagé)
│   ├── validateGameState.ts   — isValidGameState(), isValidPhase()
│   └── youtubeUtils.ts        — extractYoutubeId() (extrait de AdminHome)
│
└── Components/
    ├── GameController.tsx      — rendu pur, consomme useGameController
    ├── GameCreator.tsx         — rendu pur, consomme useGameCreationForm
    ├── SongController/
    │   ├── index.tsx           — dispatcher selon type de question
    │   ├── BlindTestController.tsx
    │   ├── MultipleChoiceController.tsx
    │   └── OpenQuestionController.tsx
    └── AdminHome.tsx           — orchestration, allégé
```

### 2.4 Diagramme de composition des contextes

```mermaid
flowchart TD
  subgraph Providers["Arbre des Providers (ordre d'imbrication)"]
    A[ApiContext.Provider] --> B[SseDispatchContext.Provider]
    B --> C[GameLifecycleContext.Provider]
    B --> D[TeamContext.Provider]
    B --> E[QuestionContext.Provider]
    C --> F[Composants UI]
    D --> F
    E --> F
  end
```

---

## 3. Game Front — `neon-beat-game-front`

### 3.1 État actuel

```mermaid
classDiagram
  class useNeonBeatPublic {
    +phase + question + teams
    +answersFound + hintsFound
    +sse: EventSource
    +connectSse()
    +onPhaseChanged()
    +onTeamCreated()
    +onAnswersFound()
    +playCorrectSound()
    +playWrongSound()
    +fetchCurrentPhase()
  }

  class App {
    +routing conditionnel (8 vues)
    +fade audio logique (timer + volume)
    +gameState depuis useNeonBeatPublic
  }
```

### 3.2 Découpage proposé

```mermaid
classDiagram
  class useSseConnection {
    +sse: EventSource
    +isReady: bool
    +on(event, handler)
    +off(event, handler)
  }

  class useGamePhase {
    +phase: GamePhase
    +question: Question
    +onPhaseChanged(handler)
  }

  class useTeamState {
    +teams: Team[]
    +onTeamCreated(handler)
    +onTeamUpdated(handler)
  }

  class useQuestionState {
    +answersFound: number[]
    +hintsFound: number[]
    +onAnswersFound(handler)
    +onHintsRevealed(handler)
  }

  class useAudioNotifications {
    +playCorrect()
    +playWrong()
  }

  class useIntroAudioFade {
    +volume: number
    +isFading: bool
    +startFade()
    +stopFade()
  }

  class useNeonBeatPublic {
    [compose les hooks ci-dessus]
    +phase + question + teams
    +answersFound + hintsFound
  }

  useNeonBeatPublic *-- useSseConnection : compose
  useNeonBeatPublic *-- useGamePhase : compose
  useNeonBeatPublic *-- useTeamState : compose
  useNeonBeatPublic *-- useQuestionState : compose
  useNeonBeatPublic *-- useAudioNotifications : compose
  App *-- useIntroAudioFade : compose
```

### 3.3 Structure de fichiers proposée

```
src/
├── hooks/
│   ├── useSseConnection.ts       — connexion SSE + reconnexion
│   ├── useGamePhase.ts           — état de phase + question
│   ├── useTeamState.ts           — liste des équipes
│   ├── useQuestionState.ts       — réponses + indices trouvés
│   ├── useAudioNotifications.ts  — sons correct/wrong
│   ├── useIntroAudioFade.ts      — fade intro (extrait de App)
│   └── useNeonBeatPublic.ts      — composition des hooks ci-dessus
│
├── utils/
│   ├── parseSseEvent.ts          — partagé avec admin-front (ou package commun)
│   └── quizzUtils.ts             — derivePropositions(), deriveOpenFoundAnswers()
│
└── components/
    ├── Quizz/
    │   ├── QuizzGame.tsx         — rendu pur, logique extraite dans quizzUtils
    │   └── ...
    └── App.tsx                   — routing pur, consomme useIntroAudioFade
```

---

## 4. Virtual Buzzer — `neon-beat-virtual-buzzer`

### 4.1 État actuel

```mermaid
classDiagram
  class useBuzzerWs {
    +socket: WebSocket
    +send(msg)
    +onPhaseChanged()
    +onPairingConfirmed()
    +reconnectLogic()
    +serializeMessage()
  }

  class usePublicSse {
    +sse: EventSource
    +teams: Team[]
    +phase: GamePhase
    +parseAndNormalizeTeam()
    +normalizeColor()
    +upsertTeam()
    +onTeamCreated()
    +onTeamUpdated()
    +onPhaseChanged()
  }
```

### 4.2 Découpage proposé

```mermaid
classDiagram
  class useWebSocketConnection {
    <<hook abstrait>>
    +socket: WebSocket
    +isConnected: bool
    +send(msg: unknown)
    +onMessage(handler)
    +reconnect()
  }

  class useBuzzerWs {
    [compose useWebSocketConnection]
    +onPhaseChanged(handler)
    +onPairingConfirmed(handler)
    +sendBuzz()
    +sendIdentification(buzzer_id)
  }

  class usePublicSseConnection {
    +sse: EventSource
    +isReady: bool
    +on(event, handler)
  }

  class useTeamSseHandlers {
    +teams: Team[]
    [s'abonne via usePublicSseConnection]
    +onTeamCreated()
    +onTeamUpdated()
  }

  class teamNormalizer {
    <<module utilitaire>>
    +normalizeColor(raw) string
    +normalizeTeam(raw) Team
    +upsertTeam(teams, team) Team[]
  }

  class usePublicSse {
    [compose les hooks ci-dessus]
    +teams + phase
  }

  useBuzzerWs *-- useWebSocketConnection : compose
  usePublicSse *-- usePublicSseConnection : compose
  usePublicSse *-- useTeamSseHandlers : compose
  useTeamSseHandlers ..> teamNormalizer : utilise
```

### 4.3 Structure de fichiers proposée

```
src/
├── hooks/
│   ├── useWebSocketConnection.ts — WS abstrait + reconnexion (réutilisable)
│   ├── useBuzzerWs.ts            — logique buzzer (compose useWebSocketConnection)
│   ├── usePublicSseConnection.ts — SSE abstrait (DRY avec game-front)
│   ├── useTeamSseHandlers.ts     — handlers équipes SSE
│   └── usePublicSse.ts           — composition
│
└── utils/
    └── teamNormalizer.ts         — fonctions pures de normalisation
```

---

## 5. Transversal — Code partagé (DRY)

Trois patterns sont réécrits dans chaque service sans abstraction commune :

### 5.1 Parsing SSE (dupliqué × 3 frontends)

```mermaid
classDiagram
  class parseSseEvent~T~ {
    <<fonction pure>>
    +parseSseEvent(event: MessageEvent) T | null
  }

  class isValidGameState {
    <<fonction pure>>
    +isValidGameState(value: unknown) value is GameState
  }

  useNeonBeatPublic ..> parseSseEvent : utilise
  GameManagementContext ..> parseSseEvent : utilise
  usePublicSse ..> parseSseEvent : utilise
  GameManagementContext ..> isValidGameState : utilise
  useNeonBeatPublic ..> isValidGameState : utilise
```

**Solution** : extraire dans un package partagé `@neon-beat/shared` ou a minima
un dossier `shared/` dans chaque repo avec les mêmes fichiers (acceptable si
les repos restent indépendants et que le partage via npm est jugé trop lourd).

### 5.2 Gestion des erreurs API (dupliqué × n appels)

```mermaid
classDiagram
  class ApiError {
    +status: number
    +message: string
    +code: string | undefined
  }

  class handleApiError {
    <<fonction pure>>
    +handleApiError(err: unknown) ApiError
    +isNetworkError(err) bool
    +isAuthError(err) bool
  }

  ApiClient ..> handleApiError : utilise
  useBuzzerWs ..> handleApiError : utilise
  usePublicSse ..> handleApiError : utilise
```

### 5.3 Reconnexion SSE (dupliqué × 3 frontends)

Les trois frontends réimplémentent la même logique de reconnexion SSE
(backoff, retry, cleanup). Cela peut être extrait en hook générique :

```typescript
// useEventSourceWithRetry.ts — partagé
function useEventSourceWithRetry(url: string, options?: {
  maxRetries?: number;
  backoffMs?: number;
}): { source: EventSource | null; isReady: boolean; reconnect: () => void }
```

---

## 6. Résumé des patterns appliqués

| Pattern | Où | Pourquoi |
|---|---|---|
| **Composition de hooks** | Tous les frontends | Un hook composite appelle des hooks spécialisés |
| **Trait + injection** | Rust backend | `GameEventPublisher` injecté dans les services (testabilité) |
| **Factory / Builder** | `QuestionSequenceBuilder` (Rust) | Construction complexe de modèles |
| **Dispatcher/Mediator** | `SseDispatchContext` (React) | Route les events SSE vers les bons contextes |
| **Adapter** | `ApiClient` | Isole fetch() du reste de l'app |
| **Pure utilities** | `parseSseEvent`, `teamNormalizer`, `quizzUtils` | Fonctions sans effet de bord, testables unitairement |

> **Règle d'or** : si un fichier a besoin d'un test, il doit être extractible
> sans dépendances cachées. Les fonctions pures et les services injectés
> sont toujours plus faciles à tester que les God objects.
