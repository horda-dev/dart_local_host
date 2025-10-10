// ignore_for_file: prefer_const_constructors

import 'package:horda_server/horda_server.dart';
import 'package:horda_local_host/horda_local_host.dart';
import 'package:test/test.dart';

// commands

abstract class TestServiceCommand extends RemoteCommand {
  @override
  Map<String, dynamic> toJson();
}

class TestCommand1 extends TestServiceCommand {
  TestCommand1();
  factory TestCommand1.fromJson(Map<String, dynamic> json) => TestCommand1();
  @override
  Map<String, dynamic> toJson() => {};
}

class TestCommand2 extends TestServiceCommand {
  TestCommand2();
  factory TestCommand2.fromJson(Map<String, dynamic> json) => TestCommand2();
  @override
  Map<String, dynamic> toJson() => {};
}

class WrongCommand extends RemoteCommand {
  WrongCommand();
  factory WrongCommand.fromJson(Map<String, dynamic> json) => WrongCommand();
  @override
  Map<String, dynamic> toJson() => {};
}

// events

abstract class TestServiceEvent extends RemoteEvent {
  @override
  Map<String, dynamic> toJson();
}

class TestEvent1 extends TestServiceEvent {
  TestEvent1(this.val);

  final String val;
  factory TestEvent1.fromJson(Map<String, dynamic> json) =>
      TestEvent1(json['val']);
  @override
  Map<String, dynamic> toJson() => {'val': val};
}

class TestEvent2 extends TestServiceEvent {
  TestEvent2(this.val);

  final String val;
  factory TestEvent2.fromJson(Map<String, dynamic> json) =>
      TestEvent2(json['val']);
  @override
  Map<String, dynamic> toJson() => {'val': val};
}

// service

class TestService implements Service {
  @override
  String get name => runtimeType.toString();

  @override
  void initHandlers(ServiceHandlers handlers) {
    handlers
      ..add<TestCommand1>(cmd1, TestCommand1.fromJson)
      ..add<TestCommand2>(cmd2, TestCommand2.fromJson);
  }

  Future<TestServiceEvent> cmd1(
    TestCommand1 cmd,
    ServiceContext context,
  ) async {
    return TestEvent1('${context.senderId}-cmd1');
  }

  Future<TestServiceEvent> cmd2(
    TestCommand2 cmd,
    ServiceContext context,
  ) async {
    return TestEvent2('${context.senderId}-cmd2');
  }
}

void main() {
  test('service should handle commands and publish events', () {
    var system = HordaServerTestSystem();
    system.start();

    system.registerService(
      TestService(),
    );

    system.sendService('TestService', 'test', TestCommand1());
    system.sendService('TestService', 'test', TestCommand2());

    expect(
      system.messageStore
          .serviceEvents(serviceName: 'TestService')
          .map((e) => e.event),
      emitsInAnyOrder([
        <String, dynamic>{'val': 'test-cmd1'},
        <String, dynamic>{'val': 'test-cmd2'},
      ]),
    );
  });

  test('service should ignore commands it cannot handle', () {
    var system = HordaServerTestSystem();
    system.start();

    system.registerService(
      TestService(),
    );

    system.sendService('TestService', 'test', WrongCommand());

    expect(
      system.messageStore
          .serviceEvents(serviceName: 'TestService')
          .map((e) => e.event),
      emits(
        <String, dynamic>{
          'msg':
              'service TestService has no json factory registered for command type: WrongCommand'
        },
      ),
    );
  });
}
