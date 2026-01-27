import 'package:horda_local_host/src/list_page_manager.dart';
import 'package:horda_local_host/src/list_view_page.dart';
import 'package:horda_local_host/src/store.dart';
import 'package:horda_server/horda_server.dart';
import 'package:mockito/annotations.dart';
import 'package:test/test.dart';

@GenerateNiceMocks([MockSpec<ViewStore>()])
import 'list_page_manager_test.mocks.dart';

void main() {
  ListViewPage createTestPage({
    required String pageId,
    required double lo,
    required double hi,
    required int limit,
    required int currentSize,
    double startAfter = 0,
    double endBefore = 0,
  }) {
    final viewKey = ViewKey('TestEntity', 'actor1', 'list1');
    final mockViewStore = MockViewStore();

    return ListViewPage(
      pageId: pageId,
      startAfter: startAfter,
      endBefore: endBefore,
      lo: lo,
      hi: hi,
      limit: limit,
      currentSize: currentSize,
      viewKey: viewKey,
      viewStore: mockViewStore,
    );
  }

  group('ListPageManager - Adding and removing pages', () {
    test('add page registers it in all tracking structures', () {
      final manager = ListPageManager();
      final page = createTestPage(
        pageId: 'page1',
        lo: 1.0,
        hi: 5.0,
        limit: 10,
        currentSize: 5,
      );

      manager.addPage(page);

      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');
      expect(manager.hasPagesForView(viewKey), true);
    });

    test('removePage removes page from all tracking structures', () {
      final manager = ListPageManager();
      final page = createTestPage(
        pageId: 'page1',
        lo: 1.0,
        hi: 5.0,
        limit: 10,
        currentSize: 5,
      );

      manager.addPage(page);
      manager.removePage('page1');

      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');
      expect(manager.hasPagesForView(viewKey), false);
    });

    test('removing non-existent page does not throw', () {
      final manager = ListPageManager();
      expect(() => manager.removePage('non-existent'), returnsNormally);
    });

    test('multiple pages for same view are all tracked', () {
      final manager = ListPageManager();

      final page1 = createTestPage(
        pageId: 'page1',
        lo: 1.0,
        hi: 5.0,
        limit: 5,
        currentSize: 5,
      );

      final page2 = createTestPage(
        pageId: 'page2',
        lo: 6.0,
        hi: 10.0,
        limit: 5,
        currentSize: 5,
      );

      manager.addPage(page1);
      manager.addPage(page2);

      final viewKey = ViewKey('TestEntity', 'actor1', 'list1');
      expect(manager.hasPagesForView(viewKey), true);

      // Remove one page, view should still have pages
      manager.removePage('page1');
      expect(manager.hasPagesForView(viewKey), true);

      // Remove second page, view should have no pages
      manager.removePage('page2');
      expect(manager.hasPagesForView(viewKey), false);
    });
  });

  group('ListPageManager - Change envelope handling', () {
    test('ListViewItemAdded affects relevant pages', () async {
      final manager = ListPageManager();

      // Create a page with room to extend
      final page = createTestPage(
        pageId: 'page1',
        lo: 1.0,
        hi: 5.0,
        limit: 10,
        currentSize: 5,
      );

      manager.addPage(page);

      final change = QueryListViewItemAdded(pos: 3.0, refId: 'actor2');
      final envelope = ChangeEnvelop(
        entityName: 'TestEntity',
        key: 'actor1',
        name: 'list1',
        changes: [change],
        changeId: '1',
      );

      final resultEnvelope = await manager.handleChangeEnvelope(envelope);

      // Should produce a ListPageItemAdded change
      expect(resultEnvelope.changes.length, 1);
      expect(resultEnvelope.changes.first, isA<ListPageItemAdded>());
      expect(
        (resultEnvelope.changes.first as ListPageItemAdded).pageId,
        'page1',
      );
      expect((resultEnvelope.changes.first as ListPageItemAdded).pos, 3.0);
      expect(
        (resultEnvelope.changes.first as ListPageItemAdded).refId,
        'actor2',
      );
    });

    test('ListViewItemRemoved affects relevant pages', () async {
      final manager = ListPageManager();

      final page = createTestPage(
        pageId: 'page1',
        lo: 1.0,
        hi: 5.0,
        limit: 10,
        currentSize: 5,
      );

      manager.addPage(page);

      final change = QueryListViewItemRemoved(pos: 3.0, refId: 'actor3');
      final envelope = ChangeEnvelop(
        entityName: 'TestEntity',
        key: 'actor1',
        name: 'list1',
        changes: [change],
        changeId: '1',
      );

      final resultEnvelope = await manager.handleChangeEnvelope(envelope);

      // Should produce a ListPageItemRemoved change
      expect(resultEnvelope.changes.length, 1);
      expect(resultEnvelope.changes.first, isA<ListPageItemRemoved>());
      expect(
        (resultEnvelope.changes.first as ListPageItemRemoved).pageId,
        'page1',
      );
      expect((resultEnvelope.changes.first as ListPageItemRemoved).pos, 3.0);
    });

    test('ListViewCleared affects all pages for that view', () async {
      final manager = ListPageManager();

      final page1 = createTestPage(
        pageId: 'page1',
        lo: 1.0,
        hi: 5.0,
        limit: 5,
        currentSize: 5,
      );

      final page2 = createTestPage(
        pageId: 'page2',
        lo: 6.0,
        hi: 10.0,
        limit: 5,
        currentSize: 5,
      );

      manager.addPage(page1);
      manager.addPage(page2);

      final change = ListViewCleared();
      final envelope = ChangeEnvelop(
        entityName: 'TestEntity',
        key: 'actor1',
        name: 'list1',
        changes: [change],
        changeId: '1',
      );

      final resultEnvelope = await manager.handleChangeEnvelope(envelope);

      // Should produce ListPageCleared for both pages
      expect(resultEnvelope.changes.length, 2);
      expect(resultEnvelope.changes.every((c) => c is ListPageCleared), true);

      final pageIds = resultEnvelope.changes
          .map((c) => (c as ListPageCleared).pageId)
          .toSet();
      expect(pageIds.contains('page1'), true);
      expect(pageIds.contains('page2'), true);
    });

    test('change for non-existent view returns original envelope', () async {
      final manager = ListPageManager();

      final change = QueryListViewItemAdded(pos: 3.0, refId: 'actor2');
      final envelope = ChangeEnvelop(
        entityName: 'TestEntity',
        key: 'actor1',
        name: 'list1',
        changes: [change],
        changeId: '1',
      );

      final resultEnvelope = await manager.handleChangeEnvelope(envelope);
      expect(resultEnvelope, same(envelope));
    });

    test('change outside page window returns original envelope', () async {
      final manager = ListPageManager();

      // Create a full page
      final page = createTestPage(
        pageId: 'page1',
        lo: 1.0,
        hi: 5.0,
        limit: 5,
        currentSize: 5,
      );

      manager.addPage(page);

      // Add item after the window when page is full
      final change = QueryListViewItemAdded(pos: 9.0, refId: 'actor2');
      final envelope = ChangeEnvelop(
        entityName: 'TestEntity',
        key: 'actor1',
        name: 'list1',
        changes: [change],
        changeId: '1',
      );

      final resultEnvelope = await manager.handleChangeEnvelope(envelope);
      expect(resultEnvelope, same(envelope));
    });
  });
}
