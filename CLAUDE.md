# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`horda_local_host` is a local development emulator for the Horda framework. It runs as a Dart server that hosts entities (actors), services, and processes defined in packages built with `horda_server`. The project uses build_runner code generation to automatically create a `bin/main.dart` file that registers and launches all components.

## Development Commands

### Build and Code Generation
- **Generate main.dart**: `dart run build_runner build`
- **Clean build cache**: `dart run build_runner clean`
- **Full regeneration**: `dart run build_runner clean && dart run build_runner build`

Note: `build_runner` only regenerates when it detects changes. Manual modifications to `bin/main.dart` require cleaning the build cache first.

### Running the Application
- **Run from command line**: `dart bin/main.dart`
- **Run in VS Code**: Press F5
- **Run tests**: `dart test`
- **Run specific test**: `dart test test/path/to/test_file.dart`

### Environment Variables
- **PORT**: HTTP server port (default: 8080)

### Client Connection
- **Local connection**: `ws://localhost:8080/client`
- **Android emulator**: `ws://10.0.2.2:8080/client` (uses special alias to reach host machine)

## Architecture

### Code Generation System (lib/src/main_builder/)

The `mainBuilder` (configured in build.yaml) scans all Dart files in `lib/` to discover:
- **Entities (Actors)**: Stateful components with command handlers and view projections
- **Services**: Stateless components that handle commands and return events
- **Processes**: Event listeners that react to dispatched events

The builder generates `bin/main.dart` which:
1. Creates a `HordaServerSystem` instance
2. Registers all discovered entities with their state and view groups
3. Registers all services
4. Registers all processes
5. Calls `system.start()` to launch the server

Key files:
- `builder.dart`: Main builder that orchestrates the analysis
- `analyzed_package.dart`: Collects entities, services, and processes from library readers
- `generator.dart`: Generates the main.dart file content
- `type_checker.dart`: Uses dart analyzer to identify Horda framework types

**Naming Conventions**: The builder expects strict naming patterns:
- Entity: `UserEntity` → State: `UserEntityState` (or `UserState`) → ViewGroup: `UserViewGroup`
- Pattern: If entity ends with "Entity", the word "Entity" is removed from ViewGroup name
- The builder will throw exceptions if it cannot find matching states or view groups

### Core System Architecture (lib/src/)

**HordaServerSystem** (system.dart) is the central orchestrator that:
- Manages message routing between entities, services, and processes
- Maintains in-memory stores (MessageStore, ViewStore, KeyValueStore)
- Tracks change IDs for view synchronization
- Starts the HTTP server for WebSocket connections
- Provides a tick mechanism for scheduled operations via CronService (fires every 1 second)

**EntityHost** (entity.dart) manages individual entity instances:
- Each entity has a unique ID and maintains its own state
- Commands are queued and processed sequentially (inbox pattern)
- State changes trigger view projections which generate ChangeEnvelops
- Supports both init handlers (creating new entities) and regular handlers
- Entity lifecycle: receive command → invoke handler → project state → update views → publish events
- Entities are lazily instantiated when first command is received

**ServiceHost** (service.dart) wraps stateless services:
- Services handle commands and return events
- No state management or queuing (processes commands directly)
- Registers command handlers with type-safe factories
- Services are registered at system startup

**ProcessHost** (process.dart) handles event-driven workflows:
- Listens to dispatched events from the system
- Can call entities and services to orchestrate multi-step operations
- Publishes ProcessResultEnvelops when complete
- Supports scheduled execution via CronService integration

**WebSocket Communication** (http.dart, ws.dart):
- HTTP server listens on port 8080 (configurable via PORT environment variable)
- Supports both authenticated (Firebase JWT) and incognito connections
- WsSession handles bidirectional communication with clients
- Message types: Query, SendCommand, CallCommand, DispatchEvent, SubscribeViews, UnsubscribeViews
- View subscriptions stream ChangeEnvelops to keep clients synchronized
- WebSocket ping interval: 5 seconds

### Message Flow

1. **Command Flow**: Client → WebSocket → MessageStore → EntityHost/ServiceHost → Handler → Event → Client
2. **Event Dispatch**: Client → DispatchEvent → MessageStore → ProcessHost → (may trigger more commands) → ProcessResult
3. **View Updates**: State change → View projection → ChangeEnvelop → MessageStore → Subscribed clients

### Store Architecture (store.dart)

- **MemoryMessageStore**: In-memory message bus with streams for commands, events, and changes
- **MemoryViewStore**: Maintains view state and applies change projections
- **MemKeyValueStore**: Simple in-memory key-value storage

All stores are in-memory only (data is lost on restart), suitable for local development.

### Testing

The project includes `HordaServerTestSystem` which provides a lighter-weight version of the system without HTTP server or cron for unit testing.

Test organization:
- `test/actor/`: Entity/actor behavior tests
- `test/flow/`: Event dispatch and process workflow tests
- `test/query/`: View query tests (uses mockito)
- `test/service/`: Service handler tests
- `test/view/`: View projection and attribute tests

## Important Patterns

### Entity State Management
Entities process commands one at a time using an inbox queue to ensure consistency. The `_idle` flag prevents concurrent command processing. Entities are lazily created on first command.

### Entity vs Service: When to Use Each
- **Use Entity** when you need:
  - State persistence across multiple commands
  - Sequential command processing per entity ID
  - View projections and real-time updates
  - Example: User accounts, shopping carts, chat rooms

- **Use Service** when you need:
  - Stateless operations
  - Simple request-response patterns
  - No view projections needed
  - Example: Authentication, calculations, external API calls

### View Projections
View changes are packaged into ChangeEnvelops with monotonically increasing changeIds tracked per view/attribute. This enables clients to resume subscriptions from a specific point.

### Error Handling
Commands that fail produce `FluirErrorEvent` instead of throwing, allowing clients to handle errors gracefully. JSON parsing errors produce detailed `HordaLocalHostJsonError` with file locations.

### Authentication
Firebase JWT tokens are extracted from the `firebaseIdToken` header. Expired tokens result in incognito connections. Incognito users can query and dispatch events but cannot send commands.

## Key Timeouts
- **Entity command call**: 500ms
- **Service command call**: 10 seconds
- **Event dispatch**: 10 seconds
