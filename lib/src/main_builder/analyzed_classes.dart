import 'package:analyzer/dart/element/element.dart';

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

class AnalyzedProcess extends AnalyzedClass {
  AnalyzedProcess(super.element);
}

class AnalyzedCommand extends AnalyzedClass {
  AnalyzedCommand(super.element);
}

class AnalyzedEvent extends AnalyzedClass {
  AnalyzedEvent(super.element);
}
