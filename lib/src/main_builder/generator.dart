class MainFuncActor {
  const MainFuncActor(this.name, this.stateName, this.viewGroupName);

  final String name;
  final String stateName;
  final String viewGroupName;
}

class MainFuncService {
  const MainFuncService(this.name);

  final String name;
}

class MainFuncProcess {
  const MainFuncProcess(this.name);

  final String name;
}

String generateMainFile(
  String packageName,
  List<MainFuncActor> actors,
  List<MainFuncService> services,
  List<MainFuncProcess> processes,
) {
  var actorRegistrations = '';
  for (final actor in actors) {
    actorRegistrations +=
        '  system.registerEntity(${actor.name}(), ${actor.viewGroupName}());\n';
  }

  var serviceRegistrations = '';
  for (final service in services) {
    serviceRegistrations += '  system.registerService(${service.name}());\n';
  }

  var processRegistrations = '';
  for (final process in processes) {
    processRegistrations += '  system.registerProcess(${process.name}());\n';
  }

  return '''
// GENERATED FILE
//
// If you have modified this file by hand, to regenerate it, you must:
// 1. Clean the build cache: `dart run build_runner clean`
// 2. Regenerate the file: `dart run build_runner build`
//
// This file is generated based on your project's entities,
// services, and processes.

// ignore_for_file: depend_on_referenced_packages

import 'package:horda_local_host/horda_local_host.dart';
import 'package:$packageName/$packageName.dart';

void main() {
  print('Local host launched!');

  final system = HordaServerSystem();

$actorRegistrations
$serviceRegistrations
$processRegistrations
  system.start();
}
''';
}
