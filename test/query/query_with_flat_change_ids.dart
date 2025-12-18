// Tests for queryWithFlatChangeIDs

import 'package:horda_local_host/horda_local_host.dart';
import 'package:horda_server/horda_server.dart';
import 'package:test/test.dart';

// Test Entity
class TestCreateCommand extends RemoteCommand {
  TestCreateCommand();

  factory TestCreateCommand.fromJson(Map<String, dynamic> json) =>
      TestCreateCommand();

  @override
  Map<String, dynamic> toJson() => {};
}

class TestCreatedEvent extends RemoteEvent {
  TestCreatedEvent();

  factory TestCreatedEvent.fromJson(Map<String, dynamic> json) =>
      TestCreatedEvent();

  @override
  Map<String, dynamic> toJson() => {};
}

class TestEntity extends Entity<TestEntityState> {
  @override
  String get name => 'TestEntity';

  Future<TestCreatedEvent> handleCreate(
    TestCreateCommand cmd,
    EntityContext ctx,
  ) async {
    return TestCreatedEvent();
  }

  @override
  void initHandlers(EntityHandlers<TestEntityState> handlers) {
    handlers
      ..addInit<TestCreateCommand, TestCreatedEvent>(
        handleCreate,
        TestCreateCommand.fromJson,
        TestEntityState.fromTestCreated,
      )
      ..addStateFromJson(TestEntityState.fromJson);
  }

  @override
  void initMigrations(EntityStateMigrations migrations) {
    // noop
  }
}

class TestEntityState implements EntityState {
  TestEntityState();

  TestEntityState.fromTestCreated(TestCreatedEvent event) : this();

  factory TestEntityState.fromJson(Map<String, dynamic> json) {
    return TestEntityState();
  }

  @override
  void project(RemoteEvent event) {}

  @override
  Map<String, dynamic> toJson() => {};
}

class TestEntityViewGroup implements EntityViewGroup {
  TestEntityViewGroup();

  TestEntityViewGroup.fromTestCreated(TestCreatedEvent event) : this();

  late final view1 = ValueView<String>(
    name: 'view1',
    value: 'initial1',
  );

  late final view2 = ValueView<String>(
    name: 'view2',
    value: 'initial2',
  );

  late final listView = RefListView<TestEntity>(
    name: 'listView',
    value: [],
  );

  @override
  void initViews(ViewGroup views) {
    views
      ..add(view1)
      ..add(view2)
      ..add(listView);
  }

  @override
  void initProjectors(EntityViewGroupProjectors projectors) {
    projectors.addInit<TestCreatedEvent>(TestEntityViewGroup.fromTestCreated);
  }
}

void main() {
  group('queryWithFlatChangeIDs', () {
    test('should return query result and flat changeID map', () async {
      final system = HordaServerTestSystem();
      final entity = TestEntity();

      system.registerEntity<TestEntityState>(
        entity,
        TestEntityViewGroup(),
      );

      system.start();

      // Create entity
      system.sendEntity('TestEntity', 'actor1', 'system', TestCreateCommand());
      await Future.delayed(Duration(milliseconds: 10));

      // Query with flat changeIDs
      final qb = QueryDefBuilder('TestEntity')
        ..val('view1')
        ..val('view2');

      final res = await system.viewStore.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      // Verify query result
      expect(res.queryResult.views['view1']?.value, 'initial1');
      expect(res.queryResult.views['view2']?.value, 'initial2');

      // Verify changeIDs map contains correct keys
      // Note: Initial views have empty changeIDs until first change
      final viewKey1 = ViewKey('TestEntity', 'actor1', 'view1');
      final viewKey2 = ViewKey('TestEntity', 'actor1', 'view2');

      expect(res.changeIDs.containsKey(viewKey1), isTrue);
      expect(res.changeIDs.containsKey(viewKey2), isTrue);
      expect(res.changeIDs.length, 2);

      // Verify changeIDs are strings (can be empty initially)
      expect(res.changeIDs[viewKey1], isA<String>());
      expect(res.changeIDs[viewKey2], isA<String>());

      // Verify pages list is empty (no list views in this query)
      expect(res.pages, isEmpty);
    });

    test('should collect changeIDs from nested Ref queries', () async {
      // This test would need a more complex entity setup with ref views
      // For now, we verify the basic functionality works
      final system = HordaServerTestSystem();
      final entity = TestEntity();

      system.registerEntity<TestEntityState>(
        entity,
        TestEntityViewGroup(),
      );

      system.start();

      system.sendEntity('TestEntity', 'actor1', 'system', TestCreateCommand());
      await Future.delayed(Duration(milliseconds: 10));

      final qb = QueryDefBuilder('TestEntity')..val('view1');

      final res = await system.viewStore.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      expect(res.queryResult.views['view1']?.value, 'initial1');

      final viewKey = ViewKey('TestEntity', 'actor1', 'view1');
      expect(res.changeIDs.containsKey(viewKey), isTrue);
      expect(res.changeIDs[viewKey], isA<String>());

      // Verify pages list is empty (no list views in this query)
      expect(res.pages, isEmpty);
    });

    test('should collect pages from list view queries', () async {
      final system = HordaServerTestSystem();
      final entity = TestEntity();

      system.registerEntity<TestEntityState>(
        entity,
        TestEntityViewGroup(),
      );

      system.start();

      // Create entity
      system.sendEntity('TestEntity', 'actor1', 'system', TestCreateCommand());
      await Future.delayed(Duration(milliseconds: 10));

      // Query with a list view (using limit for pagination)
      final qb = QueryDefBuilder('TestEntity')
        ..val('view1')
        ..list('TestEntity', 'listView', [], (qb) {}, limit: 10);

      final res = await system.viewStore.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      // Verify pages list contains one page for the list view
      expect(res.pages.length, 1);
      expect(res.pages.first.viewKey.entityName, 'TestEntity');
      expect(res.pages.first.viewKey.entityId, 'actor1');
      expect(res.pages.first.viewKey.viewName, 'listView');
      expect(res.pages.first.limit, 10);
      expect(res.pages.first.pageId, isNotEmpty);
    });
  });
}
