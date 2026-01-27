import 'package:horda_local_host/src/store.dart';
import 'package:horda_server/horda_server.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

@GenerateNiceMocks([MockSpec<MessageStore>(), MockSpec<KeyValueStore>()])
import 'pagination_query_test.mocks.dart';

void main() {
  // Helper to seed a list view with specific positions and refIds
  void seedListView(
    MockKeyValueStore snapStore,
    String entityName,
    String actorId,
    String viewName,
    List<double> positions,
    List<String> refIds,
    String changeId,
  ) {
    final items = <ListItem>[];
    for (var i = 0; i < positions.length; i++) {
      items.add(ListItem(positions[i], refIds[i]));
    }

    when(snapStore.containsKey('$entityName/$actorId/$viewName')).thenAnswer(
      (_) => Future.value(true),
    );
    when(snapStore.get('$entityName/$actorId/$viewName')).thenAnswer(
      (_) => Future.value(ViewSnapshot(items, changeId)),
    );
  }

  group('Pagination query - Empty list', () {
    test('query empty list returns empty result', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      // No seeding - empty list
      when(snapStore.containsKey('TestEntity/actor1/list1')).thenAnswer(
        (_) => Future.value(true),
      );
      when(snapStore.get('TestEntity/actor1/list1')).thenAnswer(
        (_) => Future.value(ViewSnapshot(<ListItem>[], '')),
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list('TestEntity', 'list1', [], (qb) {}, limit: 5);

      final res = await store.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      final listResult = res.queryResult.views['list1'] as ListQueryResult;
      expect(listResult.value, isEmpty);

      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');
      expect(res.changeIDs[viewKey], '');

      expect(res.pages.length, 1);
      expect(res.pages.first.currentSize, 0);
    });
  });

  group('Pagination query - Forward pagination', () {
    test('first page with no startAfter returns first N items', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      // Generate 10 items with positions
      final positions = List.generate(10, (i) => i.toDouble());
      final refIds = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        positions,
        refIds,
        '100',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list('TestEntity', 'list1', [], (qb) {}, limit: 5);

      final res = await store.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      final listResult = res.queryResult.views['list1'] as ListQueryResult;
      expect(listResult.value.length, 5);

      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');
      expect(res.changeIDs[viewKey], '100');

      // Verify we got the first 5 items
      final valueList = (listResult.value).toList();
      for (var i = 0; i < 5; i++) {
        expect(valueList[i].position, positions[i]);
        expect(valueList[i].refId, refIds[i]);
      }

      // Verify page created
      expect(res.pages.length, 1);
      expect(res.pages.first.limit, 5);
      expect(res.pages.first.currentSize, 5);
      expect(res.pages.first.lo, positions[0]);
      expect(res.pages.first.hi, positions[4]);
    });

    test('middle page with startAfter returns correct range', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      final positions = List.generate(10, (i) => i.toDouble());
      final refIds = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        positions,
        refIds,
        '100',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list(
          'TestEntity',
          'list1',
          [],
          (qb) {},
          limit: 3,
          startAfter: refIds[2],
        );

      final res = await store.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      final listResult = res.queryResult.views['list1'] as ListQueryResult;
      expect(listResult.value.length, 3);

      // Should get items at indices 3, 4, 5 (after index 2)
      final valueList = (listResult.value).toList();
      for (var i = 0; i < 3; i++) {
        expect(valueList[i].position, positions[i + 3]);
        expect(valueList[i].refId, refIds[i + 3]);
      }

      expect(res.pages.first.startAfter, positions[2]);
      expect(res.pages.first.lo, positions[3]);
      expect(res.pages.first.hi, positions[5]);
    });

    test('last page returns fewer items than limit', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      final positions = List.generate(10, (i) => i.toDouble());
      final refIds = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        positions,
        refIds,
        '100',
      );

      // Request 10 items starting after the 8th item (index 7)
      // Should only return items at indices 8 and 9
      final qb = QueryDefBuilder('TestEntity')
        ..list(
          'TestEntity',
          'list1',
          [],
          (qb) {},
          limit: 10,
          startAfter: refIds[7],
        );

      final res = await store.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      final listResult = res.queryResult.views['list1'] as ListQueryResult;
      expect(listResult.value.length, 2);

      final valueList = (listResult.value).toList();
      expect(valueList[0].position, positions[8]);
      expect(valueList[0].refId, refIds[8]);
      expect(valueList[1].position, positions[9]);
      expect(valueList[1].refId, refIds[9]);

      expect(res.pages.first.currentSize, 2);
      expect(res.pages.first.maxSize, 10);
    });

    test('exact page boundary returns exact number of items', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      final positions = List.generate(10, (i) => i.toDouble());
      final refIds = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        positions,
        refIds,
        '100',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list(
          'TestEntity',
          'list1',
          [],
          (qb) {},
          limit: 3,
          startAfter: refIds[2],
        );

      final res = await store.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      final listResult = res.queryResult.views['list1'] as ListQueryResult;
      expect(listResult.value.length, 3);
      expect(res.pages.first.currentSize, 3);
      expect(res.pages.first.maxSize, 3);
      expect(res.pages.first.isFull, true);
    });
  });

  group('Pagination query - Reverse pagination', () {
    test('reverse pagination with endBefore returns last N items', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      final positions = List.generate(10, (i) => i.toDouble());
      final refIds = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        positions,
        refIds,
        '100',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list(
          'TestEntity',
          'list1',
          [],
          (qb) {},
          limit: -5,
          endBefore: refIds[9],
        );

      final res = await store.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      final listResult = res.queryResult.views['list1'] as ListQueryResult;
      expect(listResult.value.length, 5);

      // Reverse pagination takes last N items before endBefore
      // Should get items at indices 4, 5, 6, 7, 8 (before index 9)
      final valueList = (listResult.value).toList();
      for (var i = 0; i < 5; i++) {
        expect(valueList[i].position, positions[i + 4]);
        expect(valueList[i].refId, refIds[i + 4]);
      }

      expect(res.pages.first.isReverse, true);
      expect(res.pages.first.limit, -5);
      expect(res.pages.first.endBefore, positions[9]);
    });

    test('reverse pagination without endBefore gets last N items', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      final positions = List.generate(10, (i) => i.toDouble());
      final refIds = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        positions,
        refIds,
        '100',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list('TestEntity', 'list1', [], (qb) {}, limit: -5);

      final res = await store.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      final listResult = res.queryResult.views['list1'] as ListQueryResult;
      expect(listResult.value.length, 5);

      // Should get last 5 items (indices 5-9)
      final valueList = (listResult.value).toList();
      for (var i = 0; i < 5; i++) {
        expect(valueList[i].position, positions[i + 5]);
        expect(valueList[i].refId, refIds[i + 5]);
      }

      expect(res.pages.first.isReverse, true);
      expect(res.pages.first.endBefore, 0.0);
    });
  });

  group('Pagination query - Validation errors', () {
    test('limit=0 throws ArgumentError', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      seedListView(snapStore, 'TestEntity', 'actor1', 'list1', [], [], '0');

      final qb = QueryDefBuilder('TestEntity')
        ..list('TestEntity', 'list1', [], (qb) {}, limit: 0);

      expect(
        () => store.queryForSubscription(
          actorId: 'actor1',
          name: 'test',
          query: qb.build(),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('limit can not be 0'),
          ),
        ),
      );
    });

    test('endBefore with forward pagination throws ArgumentError', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      seedListView(snapStore, 'TestEntity', 'actor1', 'list1', [], [], '0');

      final qb = QueryDefBuilder('TestEntity')
        ..list(
          'TestEntity',
          'list1',
          [],
          (qb) {},
          limit: 10,
          endBefore: 'some_key',
        );

      expect(
        () => store.queryForSubscription(
          actorId: 'actor1',
          name: 'test',
          query: qb.build(),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('endBefore can not be used with forward pagination'),
          ),
        ),
      );
    });

    test('startAfter with reverse pagination throws ArgumentError', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      seedListView(snapStore, 'TestEntity', 'actor1', 'list1', [], [], '0');

      final qb = QueryDefBuilder('TestEntity')
        ..list(
          'TestEntity',
          'list1',
          [],
          (qb) {},
          limit: -10,
          startAfter: 'some_key',
        );

      expect(
        () => store.queryForSubscription(
          actorId: 'actor1',
          name: 'test',
          query: qb.build(),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('startAfter can not be used with reverse pagination'),
          ),
        ),
      );
    });
  });

  group('Pagination query - Boundary conditions', () {
    test('single item list with limit=1 returns that item', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      final positions = [0.0];
      final refIds = ['item0'];

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        positions,
        refIds,
        '1',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list('TestEntity', 'list1', [], (qb) {}, limit: 1);

      final res = await store.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      final listResult = res.queryResult.views['list1'] as ListQueryResult;
      expect(listResult.value.length, 1);
      final valueList = (listResult.value).toList();
      expect(valueList[0].position, positions[0]);
      expect(valueList[0].refId, refIds[0]);
      expect(res.pages.first.currentSize, 1);
      expect(res.pages.first.isFull, true);
    });

    test('limit larger than total items returns all items', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      final positions = List.generate(3, (i) => i.toDouble());
      final refIds = List.generate(3, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        positions,
        refIds,
        '1',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list('TestEntity', 'list1', [], (qb) {}, limit: 100);

      final res = await store.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      final listResult = res.queryResult.views['list1'] as ListQueryResult;
      expect(listResult.value.length, 3);
      expect(res.pages.first.currentSize, 3);
      expect(res.pages.first.maxSize, 100);
      expect(res.pages.first.isFull, false);
    });

    test('startAfter pointing to last item returns empty result', () async {
      final snapStore = MockKeyValueStore();
      final messageStore = MockMessageStore();
      final store = MemoryViewStore(snapStore, messageStore);

      final positions = List.generate(5, (i) => i.toDouble());
      final refIds = List.generate(5, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        positions,
        refIds,
        '1',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list(
          'TestEntity',
          'list1',
          [],
          (qb) {},
          limit: 10,
          startAfter: refIds[4],
        );

      final res = await store.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      final listResult = res.queryResult.views['list1'] as ListQueryResult;
      expect(listResult.value, isEmpty);
      expect(res.pages.first.currentSize, 0);
    });
  });
}
