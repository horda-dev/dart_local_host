import 'package:horda_local_host/src/list_view_page.dart';
import 'package:horda_local_host/src/store.dart';
import 'package:horda_server/horda_server.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

@GenerateNiceMocks([MockSpec<ViewStore>()])
import 'list_view_page_sync_test.mocks.dart';

void main() {
  group('Real-time sync - Backfill scenarios', () {
    test('forward page: item removed, backfill from ahead (hi+1)', () async {
      final mockViewStore = MockViewStore();
      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

      final page = ListViewPage(
        pageId: 'page1',
        startAfter: '',
        endBefore: '',
        lo: 'key2',
        hi: 'key5',
        limit: 5,
        currentSize: 4,
        viewKey: viewKey,
        viewStore: mockViewStore,
      );

      // Mock getNextListItem to return the backfill item
      when(
        mockViewStore.getNextListItem(
          'TestEntity',
          'actor1',
          'list1',
          'key5',
        ),
      ).thenAnswer((_) async => ListItem('key6', 'actor6'));

      // Remove an item from the page
      final change = ListViewItemRemoved('key3');
      final changes = await page.handleItemRemoved(change);

      // Should return 2 changes: removal + backfill
      expect(changes.length, 2);

      // First change: item removed
      expect(changes[0], isA<ListPageItemRemoved>());
      expect((changes[0] as ListPageItemRemoved).pageId, 'page1');
      expect((changes[0] as ListPageItemRemoved).key, 'key3');

      // Second change: backfill item added
      expect(changes[1], isA<ListPageItemAdded>());
      expect((changes[1] as ListPageItemAdded).pageId, 'page1');
      expect((changes[1] as ListPageItemAdded).key, 'key6');
      expect((changes[1] as ListPageItemAdded).value, 'actor6');

      // Verify page state updated correctly
      expect(page.lo, 'key2'); // lo unchanged
      expect(page.hi, 'key6'); // hi updated to backfill key
      expect(page.currentSize, 4); // size maintained
    });

    test('reverse page: item removed, backfill from behind (lo-1)', () async {
      final mockViewStore = MockViewStore();
      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

      final page = ListViewPage(
        pageId: 'page1',
        startAfter: '',
        endBefore: 'key99',
        lo: 'key5',
        hi: 'key9',
        limit: -5,
        currentSize: 4,
        viewKey: viewKey,
        viewStore: mockViewStore,
      );

      // Mock getPreviousListItem to return the backfill item
      when(
        mockViewStore.getPreviousListItem(
          'TestEntity',
          'actor1',
          'list1',
          'key5',
        ),
      ).thenAnswer((_) async => ListItem('key3', 'actor3'));

      // Remove an item from the page
      final change = ListViewItemRemoved('key7');
      final changes = await page.handleItemRemoved(change);

      // Should return 2 changes: removal + backfill
      expect(changes.length, 2);

      // First change: item removed
      expect(changes[0], isA<ListPageItemRemoved>());
      expect((changes[0] as ListPageItemRemoved).pageId, 'page1');
      expect((changes[0] as ListPageItemRemoved).key, 'key7');

      // Second change: backfill item added
      expect(changes[1], isA<ListPageItemAdded>());
      expect((changes[1] as ListPageItemAdded).pageId, 'page1');
      expect((changes[1] as ListPageItemAdded).key, 'key3');
      expect((changes[1] as ListPageItemAdded).value, 'actor3');

      // Verify page state updated correctly
      expect(page.lo, 'key3'); // lo updated to backfill key
      expect(page.hi, 'key9'); // hi unchanged
      expect(page.currentSize, 4); // size maintained
    });

    test(
      'item removed with no backfill available returns only removal',
      () async {
        final mockViewStore = MockViewStore();
        final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

        final page = ListViewPage(
          pageId: 'page1',
          startAfter: '',
          endBefore: '',
          lo: 'key2',
          hi: 'key5',
          limit: 5,
          currentSize: 3,
          viewKey: viewKey,
          viewStore: mockViewStore,
        );

        // Mock getNextListItem to return null (no backfill available)
        when(
          mockViewStore.getNextListItem(
            'TestEntity',
            'actor1',
            'list1',
            'key5',
          ),
        ).thenAnswer((_) async => null);

        final change = ListViewItemRemoved('key3');
        final changes = await page.handleItemRemoved(change);

        // Should return only 1 change: removal (no backfill)
        // Note: ListPageManager will send the original change envelop with the ListView* changes
        // when no ListPage* changes were produced by the pages.
        expect(changes.length, 1);
        expect(changes[0], isA<ListPageItemRemoved>());
        expect((changes[0] as ListPageItemRemoved).key, 'key3');
        expect((changes[0] as ListPageItemRemoved).pageId, 'page1');

        // Verify page state: size decremented, boundaries unchanged
        expect(page.lo, 'key2');
        expect(page.hi, 'key5');
        expect(page.currentSize, 2); // decremented from 3 to 2
      },
    );
  });

  group('Real-time sync - Pushout scenarios', () {
    test(
      'reverse page full, endBefore empty, item added after hi, lo pushed out',
      () async {
        final mockViewStore = MockViewStore();
        final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

        final page = ListViewPage(
          pageId: 'page1',
          startAfter: '',
          endBefore: '', // No endBefore constraint
          lo: 'key2',
          hi: 'key6',
          limit: -5,
          currentSize: 5,
          viewKey: viewKey,
          viewStore: mockViewStore,
        );

        // Mock getNextListItem to return the item after old lo
        when(
          mockViewStore.getNextListItem(
            'TestEntity',
            'actor1',
            'list1',
            'key2',
          ),
        ).thenAnswer((_) async => ListItem('key3', 'actor3'));

        // Add item after the window
        final change = ListViewItemAdded('key9', 'actor9');
        final changes = await page.handleItemAdded(change);

        // Should return 2 changes: old lo removed + new item added
        expect(changes.length, 2);

        // First change: old lo (key2) removed (pushed out)
        expect(changes[0], isA<ListPageItemRemoved>());
        expect((changes[0] as ListPageItemRemoved).pageId, 'page1');
        expect((changes[0] as ListPageItemRemoved).key, 'key2');

        // Second change: new item added at the end
        expect(changes[1], isA<ListPageItemAdded>());
        expect((changes[1] as ListPageItemAdded).pageId, 'page1');
        expect((changes[1] as ListPageItemAdded).key, 'key9');
        expect((changes[1] as ListPageItemAdded).value, 'actor9');

        // Verify page boundaries shifted
        expect(page.lo, 'key3'); // lo shifted from key2 to key3
        expect(page.hi, 'key9'); // hi shifted from key6 to key9
        expect(page.currentSize, 5); // size maintained (still full)
      },
    );

    test(
      'reverse page full with endBefore constraint, item within bounds triggers pushout',
      () async {
        final mockViewStore = MockViewStore();
        final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

        final page = ListViewPage(
          pageId: 'page1',
          startAfter: '',
          endBefore: 'key99',
          lo: 'key10',
          hi: 'key50',
          limit: -5,
          currentSize: 5,
          viewKey: viewKey,
          viewStore: mockViewStore,
        );

        // Mock getNextListItem
        when(
          mockViewStore.getNextListItem(
            'TestEntity',
            'actor1',
            'list1',
            'key10',
          ),
        ).thenAnswer((_) async => ListItem('key15', 'actor15'));

        // Add item after hi but before endBefore
        final change = ListViewItemAdded('key60', 'actor60');
        final changes = await page.handleItemAdded(change);

        // Should return 2 changes: pushout
        expect(changes.length, 2);
        expect(changes[0], isA<ListPageItemRemoved>());
        expect((changes[0] as ListPageItemRemoved).key, 'key10');
        expect(changes[1], isA<ListPageItemAdded>());
        expect((changes[1] as ListPageItemAdded).key, 'key60');

        expect(page.lo, 'key15');
        expect(page.hi, 'key60');
      },
    );

    test('reverse page full, item beyond endBefore, no pushout', () async {
      final mockViewStore = MockViewStore();
      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

      final page = ListViewPage(
        pageId: 'page1',
        startAfter: '',
        endBefore: 'key50',
        lo: 'key10',
        hi: 'key40',
        limit: -5,
        currentSize: 5,
        viewKey: viewKey,
        viewStore: mockViewStore,
      );

      // Add item beyond endBefore constraint
      final change = ListViewItemAdded('key60', 'actor60');
      final changes = await page.handleItemAdded(change);

      // Should return empty (item beyond endBefore boundary)
      expect(changes, isEmpty);

      // Page state unchanged
      expect(page.lo, 'key10');
      expect(page.hi, 'key40');
      expect(page.currentSize, 5);
    });

    test('forward page full, item added after hi, no pushout', () async {
      final mockViewStore = MockViewStore();
      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

      final page = ListViewPage(
        pageId: 'page1',
        startAfter: '',
        endBefore: '',
        lo: 'key2',
        hi: 'key6',
        limit: 5, // Forward pagination (positive limit)
        currentSize: 5,
        viewKey: viewKey,
        viewStore: mockViewStore,
      );

      // Add item after the window
      final change = ListViewItemAdded('key9', 'actor9');
      final changes = await page.handleItemAdded(change);

      // Forward pages don't pushout, they just ignore when full
      expect(changes, isEmpty);

      // Page state unchanged
      expect(page.lo, 'key2');
      expect(page.hi, 'key6');
      expect(page.currentSize, 5);
    });
  });

  group('Real-time sync - Edge cases', () {
    test('item removed outside page window returns empty', () async {
      final mockViewStore = MockViewStore();
      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

      final page = ListViewPage(
        pageId: 'page1',
        startAfter: '',
        endBefore: '',
        lo: 'key5',
        hi: 'key9',
        limit: 5,
        currentSize: 3,
        viewKey: viewKey,
        viewStore: mockViewStore,
      );

      // Remove item before lo
      final change = ListViewItemRemoved('key2');
      final changes = await page.handleItemRemoved(change);

      expect(changes, isEmpty);
      expect(page.currentSize, 3); // unchanged
    });

    test('item added inside window with room extends page', () async {
      final mockViewStore = MockViewStore();
      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

      final page = ListViewPage(
        pageId: 'page1',
        startAfter: '',
        endBefore: '',
        lo: 'key2',
        hi: 'key5',
        limit: 10,
        currentSize: 3,
        viewKey: viewKey,
        viewStore: mockViewStore,
      );

      final change = ListViewItemAdded('key3', 'actor3');
      final changes = await page.handleItemAdded(change);

      // Should return 1 change: item added
      expect(changes.length, 1);
      expect(changes[0], isA<ListPageItemAdded>());
      expect((changes[0] as ListPageItemAdded).key, 'key3');

      expect(page.currentSize, 4); // incremented
    });

    test('pushout with no next item returns empty', () async {
      final mockViewStore = MockViewStore();
      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

      final page = ListViewPage(
        pageId: 'page1',
        startAfter: '',
        endBefore: '',
        lo: 'key2',
        hi: 'key6',
        limit: -5,
        currentSize: 5,
        viewKey: viewKey,
        viewStore: mockViewStore,
      );

      // Mock getNextListItem to return null
      when(
        mockViewStore.getNextListItem(
          'TestEntity',
          'actor1',
          'list1',
          'key2',
        ),
      ).thenAnswer((_) async => null);

      final change = ListViewItemAdded('key9', 'actor9');
      final changes = await page.handleItemAdded(change);

      // Should return empty (can't pushout without finding next item)
      expect(changes, isEmpty);
    });
  });

  group('Real-time sync - Clear scenarios', () {
    test(
      'list cleared resets currentSize to zero and preserves boundaries',
      () {
        final mockViewStore = MockViewStore();
        final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

        final page = ListViewPage(
          pageId: 'page1',
          startAfter: '',
          endBefore: '',
          lo: 'key2',
          hi: 'key9',
          limit: 10,
          currentSize: 5,
          viewKey: viewKey,
          viewStore: mockViewStore,
        );

        final change = ListViewCleared();
        final changes = page.handleCleared(change);

        // Should return single ListPageCleared change
        expect(changes.length, 1);
        expect(changes[0], isA<ListPageCleared>());
        expect((changes[0] as ListPageCleared).pageId, 'page1');

        // Verify page state: currentSize reset, boundaries preserved
        expect(page.currentSize, 0);
        expect(page.lo, 'key2');
        expect(page.hi, 'key9');
      },
    );

    test('list cleared on empty page returns cleared change', () {
      final mockViewStore = MockViewStore();
      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

      final page = ListViewPage(
        pageId: 'page1',
        startAfter: '',
        endBefore: '',
        lo: 'key2',
        hi: 'key9',
        limit: 10,
        currentSize: 0,
        viewKey: viewKey,
        viewStore: mockViewStore,
      );

      final change = ListViewCleared();
      final changes = page.handleCleared(change);

      // Should return ListPageCleared change
      expect(changes.length, 1);
      expect(changes[0], isA<ListPageCleared>());
      expect((changes[0] as ListPageCleared).pageId, 'page1');

      // Verify page state unchanged
      expect(page.currentSize, 0);
      expect(page.lo, 'key2');
      expect(page.hi, 'key9');
    });
  });

  group('Real-time sync - AddIfAbsent scenarios', () {
    test('item added if absent behaves like normal add', () async {
      final mockViewStore = MockViewStore();
      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

      final page = ListViewPage(
        pageId: 'page1',
        startAfter: '',
        endBefore: '',
        lo: 'key2',
        hi: 'key5',
        limit: 10,
        currentSize: 3,
        viewKey: viewKey,
        viewStore: mockViewStore,
      );

      final change = ListViewItemAddedIfAbsent('key3', 'actor3');
      final changes = await page.handleItemAddedIfAbsent(change);

      // Should return single ListPageItemAdded change
      expect(changes.length, 1);
      expect(changes[0], isA<ListPageItemAdded>());
      expect((changes[0] as ListPageItemAdded).pageId, 'page1');
      expect((changes[0] as ListPageItemAdded).key, 'key3');
      expect((changes[0] as ListPageItemAdded).value, 'actor3');

      // Verify page state updated
      expect(page.currentSize, 4);
      expect(page.lo, 'key2');
      expect(page.hi, 'key5');
    });

    test('item added if absent on full page behaves like normal add', () async {
      final mockViewStore = MockViewStore();
      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');

      final page = ListViewPage(
        pageId: 'page1',
        startAfter: '',
        endBefore: '',
        lo: 'key2',
        hi: 'key6',
        limit: 5,
        currentSize: 5,
        viewKey: viewKey,
        viewStore: mockViewStore,
      );

      // Add item after the window on a full page
      final change = ListViewItemAddedIfAbsent('key9', 'actor9');
      final changes = await page.handleItemAddedIfAbsent(change);

      // Should return empty (full forward page ignores items after window)
      expect(changes, isEmpty);

      // Verify page state unchanged
      expect(page.currentSize, 5);
      expect(page.lo, 'key2');
      expect(page.hi, 'key6');
    });
  });
}
