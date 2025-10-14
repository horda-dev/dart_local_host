# Horda Local Emulator

Run the entire Horda platform on your development machine. Prototype, develop and test your Horda backend locally and deploy it to the Horda cloud platform once it's ready for production usage.

`horda_local_host` emulates the full Horda backend locally, giving you:
- **Complete feature parity**: Entity states, view groups, services, processes, and real-time data synchronization
- **Instant feedback**: Connect your Flutter app directly to your local backend via WebSocket
- **Run in VSCode**: Just press **F5** in Visual Studio Code with your Horda backend package open and start developing

Perfect for local development, testing, and iterating on your Horda applications without touching the cloud.

## Usage

### 1. Add as a Development Dependency
Add `horda_local_host` as a development dependency to your project:

```bash
dart pub add dev:horda_local_host
```

Alternatively, you can manually add it to your project's `pubspec.yaml` file:

```yaml
dev_dependencies:
  horda_local_host: ^0.1.0 # Use the appropriate version
```

Then, fetch all necessary Dart packages by running:
```bash
dart pub get
```

### 2. Generate Code
This project uses `build_runner` to generate the `bin/main.dart` file, which is essential for running the application.
To generate the code:
```bash
dart run build_runner build
```
Note that `build_runner` will only regenerate `bin/main.dart` if it detects changes in other Dart files. If you have manually modified `bin/main.dart` and wish to regenerate it, you must first clean the build cache before running the build command again.

```bash
dart run build_runner clean
dart run build_runner build
```

### 3. Run the Application
After generating the `main.dart` file, you can run the local host in VSCode by pressing F5. Alternatively, you can run it from the command line as usual:
```bash
dart bin/main.dart
```

### 4. Connect Client
To connect your client application to the local host, use the following WebSocket address:

```
ws://localhost:8080/client
```

**Note for Android Emulators:**
If you are running your client application on an Android emulator, `localhost` refers to the emulator's own loopback interface, not your development machine. To connect to the local host running on your development machine from an Android emulator, you must use the special alias `10.0.2.2` instead of `localhost`.

Therefore, the WebSocket address for Android emulators would be:

```
ws://10.0.2.2:8080/client
```