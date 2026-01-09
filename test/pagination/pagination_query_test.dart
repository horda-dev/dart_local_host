import 'package:horda_local_host/src/store.dart';
import 'package:horda_server/horda_server.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:xid/xid.dart';

@GenerateNiceMocks([MockSpec<MessageStore>(), MockSpec<KeyValueStore>()])
import 'pagination_query_test.mocks.dart';

void main() {
  // Helper to seed a list view with specific keys
  void seedListView(
    MockKeyValueStore snapStore,
    String entityName,
    String actorId,
    String viewName,
    List<String> keys,
    List<String> values,
    String changeId,
  ) {
    final items = <ListItem>[];
    for (var i = 0; i < keys.length; i++) {
      items.add(ListItem(keys[i], values[i]));
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
      final store = MemoryViewStore(snapStore);

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
      final store = MemoryViewStore(snapStore);

      // Generate 10 items with sorted XIDs
      final keys = List.generate(10, (_) => Xid().toString());
      keys.sort();
      final values = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        keys,
        values,
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
        expect(valueList[i].key, keys[i]);
        expect(valueList[i].value, values[i]);
      }

      // Verify page created
      expect(res.pages.length, 1);
      expect(res.pages.first.limit, 5);
      expect(res.pages.first.currentSize, 5);
      expect(res.pages.first.lo, keys[0]);
      expect(res.pages.first.hi, keys[4]);
    });

    test('middle page with startAfter returns correct range', () async {
      final snapStore = MockKeyValueStore();
      final store = MemoryViewStore(snapStore);

      final keys = List.generate(10, (_) => Xid().toString());
      keys.sort();
      final values = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        keys,
        values,
        '100',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list(
          'TestEntity',
          'list1',
          [],
          (qb) {},
          limit: 3,
          startAfter: keys[2],
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
        expect(valueList[i].key, keys[i + 3]);
        expect(valueList[i].value, values[i + 3]);
      }

      expect(res.pages.first.startAfter, keys[2]);
      expect(res.pages.first.lo, keys[3]);
      expect(res.pages.first.hi, keys[5]);
    });

    test('last page returns fewer items than limit', () async {
      final snapStore = MockKeyValueStore();
      final store = MemoryViewStore(snapStore);

      final keys = List.generate(10, (_) => Xid().toString());
      keys.sort();
      final values = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        keys,
        values,
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
          startAfter: keys[7],
        );

      final res = await store.queryForSubscription(
        actorId: 'actor1',
        name: 'test',
        query: qb.build(),
      );

      final listResult = res.queryResult.views['list1'] as ListQueryResult;
      expect(listResult.value.length, 2);

      final valueList = (listResult.value).toList();
      expect(valueList[0].key, keys[8]);
      expect(valueList[0].value, values[8]);
      expect(valueList[1].key, keys[9]);
      expect(valueList[1].value, values[9]);

      expect(res.pages.first.currentSize, 2);
      expect(res.pages.first.maxSize, 10);
    });

    test('exact page boundary returns exact number of items', () async {
      final snapStore = MockKeyValueStore();
      final store = MemoryViewStore(snapStore);

      final keys = List.generate(10, (_) => Xid().toString());
      keys.sort();
      final values = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        keys,
        values,
        '100',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list(
          'TestEntity',
          'list1',
          [],
          (qb) {},
          limit: 3,
          startAfter: keys[2],
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
      final store = MemoryViewStore(snapStore);

      final keys = List.generate(10, (_) => Xid().toString());
      keys.sort();
      final values = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        keys,
        values,
        '100',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list(
          'TestEntity',
          'list1',
          [],
          (qb) {},
          limit: -5,
          endBefore: keys[9],
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
        expect(valueList[i].key, keys[i + 4]);
        expect(valueList[i].value, values[i + 4]);
      }

      expect(res.pages.first.isReverse, true);
      expect(res.pages.first.limit, -5);
      expect(res.pages.first.endBefore, keys[9]);
    });

    test('reverse pagination without endBefore gets last N items', () async {
      final snapStore = MockKeyValueStore();
      final store = MemoryViewStore(snapStore);

      final keys = List.generate(10, (_) => Xid().toString());
      keys.sort();
      final values = List.generate(10, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        keys,
        values,
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
        expect(valueList[i].key, keys[i + 5]);
        expect(valueList[i].value, values[i + 5]);
      }

      expect(res.pages.first.isReverse, true);
      expect(res.pages.first.endBefore, '');
    });
  });

  group('Pagination query - Validation errors', () {
    test('limit=0 throws ArgumentError', () async {
      final snapStore = MockKeyValueStore();
      final store = MemoryViewStore(snapStore);

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
      final store = MemoryViewStore(snapStore);

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
      final store = MemoryViewStore(snapStore);

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
      final store = MemoryViewStore(snapStore);

      final keys = [Xid().toString()];
      final values = ['item0'];

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        keys,
        values,
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
      expect(valueList[0].key, keys[0]);
      expect(valueList[0].value, values[0]);
      expect(res.pages.first.currentSize, 1);
      expect(res.pages.first.isFull, true);
    });

    test('limit larger than total items returns all items', () async {
      final snapStore = MockKeyValueStore();
      final store = MemoryViewStore(snapStore);

      final keys = List.generate(3, (_) => Xid().toString());
      keys.sort();
      final values = List.generate(3, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        keys,
        values,
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
      final store = MemoryViewStore(snapStore);

      final keys = List.generate(5, (_) => Xid().toString());
      keys.sort();
      final values = List.generate(5, (i) => 'item$i');

      seedListView(
        snapStore,
        'TestEntity',
        'actor1',
        'list1',
        keys,
        values,
        '1',
      );

      final qb = QueryDefBuilder('TestEntity')
        ..list(
          'TestEntity',
          'list1',
          [],
          (qb) {},
          limit: 10,
          startAfter: keys[4],
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
