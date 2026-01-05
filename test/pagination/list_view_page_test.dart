import 'package:horda_local_host/src/list_view_page.dart';
import 'package:horda_local_host/src/store.dart';
import 'package:mockito/annotations.dart';
import 'package:test/test.dart';

@GenerateNiceMocks([MockSpec<ViewStore>()])
import 'list_view_page_test.mocks.dart';

void main() {
  // Helper function to create a forward pagination ListViewPage for testing
  ListViewPage newTestPage({
    required String lo,
    required String hi,
    required int limit,
    required int currentSize,
    String startAfter = '',
    String endBefore = '',
  }) {
    final viewKey = ViewKey('TestEntity', 'actor1', 'list1');
    final mockViewStore = MockViewStore();

    return ListViewPage(
      pageId: 'test-page',
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

  // Helper function to create a reverse pagination ListViewPage for testing
  ListViewPage newTestReversePage({
    required String lo,
    required String hi,
    required String endBefore,
    required int limit,
    required int currentSize,
  }) {
    final viewKey = ViewKey('TestEntity', 'actor1', 'list1');
    final mockViewStore = MockViewStore();

    return ListViewPage(
      pageId: 'test-page',
      startAfter: '',
      endBefore: endBefore,
      lo: lo,
      hi: hi,
      limit: limit < 0 ? limit : -limit, // Ensure negative for reverse
      currentSize: currentSize,
      viewKey: viewKey,
      viewStore: mockViewStore,
    );
  }

  group('ListViewPage - Helper methods', () {
    test('maxSize returns absolute value of limit (positive)', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.maxSize, 10);
    });

    test('maxSize returns absolute value of limit (negative)', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: -10,
        currentSize: 5,
      );
      expect(page.maxSize, 10);
    });

    test('isReverse returns false for positive limit', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isReverse, false);
    });

    test('isReverse returns true for negative limit', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: -10,
        currentSize: 5,
      );
      expect(page.isReverse, true);
    });

    test('isFull returns true when currentSize equals maxSize', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: 5,
        currentSize: 5,
      );
      expect(page.isFull, true);
    });

    test('isFull returns false when currentSize less than maxSize', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isFull, false);
    });

    test('isEmpty returns true when currentSize is zero', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: 10,
        currentSize: 0,
      );
      expect(page.isEmpty, true);
    });

    test('isEmpty returns false when currentSize is non-zero', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isEmpty, false);
    });

    test('canExtendWindow returns true when not full', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.canExtendWindow(), true);
    });

    test('canExtendWindow returns false when full', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: 5,
        currentSize: 5,
      );
      expect(page.canExtendWindow(), false);
    });
  });

  group('ListViewPage - Boundary detection', () {
    test('isInsideWindow returns true for key between lo and hi', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindow('key5'), true);
    });

    test('isInsideWindow returns false for key at lo boundary', () {
      final page = newTestPage(
        lo: 'key5',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindow('key5'), false);
    });

    test('isInsideWindow returns false for key at hi boundary', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key5',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindow('key5'), false);
    });

    test('isInsideWindow returns false for key before lo', () {
      final page = newTestPage(
        lo: 'key5',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindow('key2'), false);
    });

    test('isInsideWindow returns false for key after hi', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key5',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindow('key9'), false);
    });

    test('isInsideWindowInclusive returns true for key at lo boundary', () {
      final page = newTestPage(
        lo: 'key5',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindowInclusive('key5'), true);
    });

    test('isInsideWindowInclusive returns true for key at hi boundary', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key5',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindowInclusive('key5'), true);
    });

    test('isInsideWindowInclusive returns true for key between lo and hi', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindowInclusive('key5'), true);
    });

    test('isInsideWindowInclusive returns false for key before lo', () {
      final page = newTestPage(
        lo: 'key5',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindowInclusive('key2'), false);
    });

    test('isInsideWindowInclusive returns false for key after hi', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key5',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindowInclusive('key9'), false);
    });

    test('isAfterWindow returns true for key after hi', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key5',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isAfterWindow('key9'), true);
    });

    test('isAfterWindow returns false for key at hi', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key5',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isAfterWindow('key5'), false);
    });

    test('isAfterWindow returns false for key before hi', () {
      final page = newTestPage(
        lo: 'key1',
        hi: 'key9',
        limit: 10,
        currentSize: 5,
      );
      expect(page.isAfterWindow('key5'), false);
    });
  });

  group('ListViewPage - canExtendBeyond', () {
    test('canExtendBeyond returns true when no endBefore constraint', () {
      final page = newTestReversePage(
        lo: 'key1',
        hi: 'key20',
        endBefore: '',
        limit: 10,
        currentSize: 5,
      );
      expect(page.canExtendBeyond('key999'), true);
    });

    test('canExtendBeyond returns true when key before endBefore', () {
      final page = newTestReversePage(
        lo: 'key1',
        hi: 'key20',
        endBefore: 'key50',
        limit: 10,
        currentSize: 5,
      );
      expect(page.canExtendBeyond('key30'), true);
    });

    test('canExtendBeyond returns false when key equals endBefore', () {
      final page = newTestReversePage(
        lo: 'key1',
        hi: 'key20',
        endBefore: 'key50',
        limit: 10,
        currentSize: 5,
      );
      expect(page.canExtendBeyond('key50'), false);
    });

    test('canExtendBeyond returns false when key after endBefore', () {
      final page = newTestReversePage(
        lo: 'key1',
        hi: 'key20',
        endBefore: 'key50',
        limit: 10,
        currentSize: 5,
      );
      expect(page.canExtendBeyond('key60'), false);
    });
  });
}
