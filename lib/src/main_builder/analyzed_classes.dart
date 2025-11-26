import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';

import 'type_checker.dart';

class AnalyzedClass {
  AnalyzedClass(this.element);

  final ClassElement element;

  String get name {
    return element.name ?? 'NO-NAME';
  }
}

class AnalyzedActor extends AnalyzedClass {
  AnalyzedActor(super.element);

  late AnalyzedState state;
  late AnalyzedViewGroup viewGroup;

  void linkState(AnalyzedState state) {
    this.state = state;
  }

  void linkViewGroup(AnalyzedViewGroup viewGroup) {
    this.viewGroup = viewGroup;
  }
}

class AnalyzedState extends AnalyzedClass {
  AnalyzedState(super.element);
}

class AnalyzedViewGroup extends AnalyzedClass {
  AnalyzedViewGroup(super.element);
}

class AnalyzedService extends AnalyzedClass {
  AnalyzedService(super.element);
}

class AnalyzedProcessGroup extends AnalyzedClass {
  AnalyzedProcessGroup(super.element);

  Set<String> get eventTypes {
    final processes = element.methods.where(
      (m) => HordaTypeChecker.instance.isProcess(m),
    );

    final names = processes.map((p) {
      final firstParameterType = p.formalParameters.first.type
          .getDisplayString();

      if (firstParameterType.isEmpty) {
        log.warning(
          'Failed to extract process name in method: ${p.displayName}',
        );
        return 'NO_NAME';
      }

      return firstParameterType;
    });

    return names.toSet();
  }
}

class AnalyzedCommand extends AnalyzedClass {
  AnalyzedCommand(super.element);
}

class AnalyzedEvent extends AnalyzedClass {
  AnalyzedEvent(super.element);
}
