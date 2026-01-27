import 'package:horda_local_host/src/list_view_page.dart';
import 'package:horda_local_host/src/store.dart';
import 'package:mockito/annotations.dart';
import 'package:test/test.dart';

@GenerateNiceMocks([MockSpec<ViewStore>()])
import 'list_view_page_test.mocks.dart';

void main() {
  // Helper function to create a forward pagination ListViewPage for testing
  ListViewPage newTestPage({
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
    required double lo,
    required double hi,
    required double endBefore,
    required int limit,
    required int currentSize,
  }) {
    final viewKey = ViewKey('TestEntity', 'actor1', 'list1');
    final mockViewStore = MockViewStore();

    return ListViewPage(
      pageId: 'test-page',
      startAfter: 0,
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
        lo: 1.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.maxSize, 10);
    });

    test('maxSize returns absolute value of limit (negative)', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: -10,
        currentSize: 5,
      );
      expect(page.maxSize, 10);
    });

    test('isReverse returns false for positive limit', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isReverse, false);
    });

    test('isReverse returns true for negative limit', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: -10,
        currentSize: 5,
      );
      expect(page.isReverse, true);
    });

    test('isFull returns true when currentSize equals maxSize', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: 5,
        currentSize: 5,
      );
      expect(page.isFull, true);
    });

    test('isFull returns false when currentSize less than maxSize', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isFull, false);
    });

    test('isEmpty returns true when currentSize is zero', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: 10,
        currentSize: 0,
      );
      expect(page.isEmpty, true);
    });

    test('isEmpty returns false when currentSize is non-zero', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isEmpty, false);
    });

    test('canExtendWindow returns true when not full', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.canExtendWindow(), true);
    });

    test('canExtendWindow returns false when full', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: 5,
        currentSize: 5,
      );
      expect(page.canExtendWindow(), false);
    });
  });

  group('ListViewPage - Boundary detection', () {
    test('isInsideWindow returns true for pos between lo and hi', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindow(5.0), true);
    });

    test('isInsideWindow returns false for pos at lo boundary', () {
      final page = newTestPage(
        lo: 5.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindow(5.0), false);
    });

    test('isInsideWindow returns false for pos at hi boundary', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 5.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindow(5.0), false);
    });

    test('isInsideWindow returns false for pos before lo', () {
      final page = newTestPage(
        lo: 5.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindow(2.0), false);
    });

    test('isInsideWindow returns false for pos after hi', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 5.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindow(9.0), false);
    });

    test('isInsideWindowInclusive returns true for pos at lo boundary', () {
      final page = newTestPage(
        lo: 5.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindowInclusive(5.0), true);
    });

    test('isInsideWindowInclusive returns true for pos at hi boundary', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 5.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindowInclusive(5.0), true);
    });

    test('isInsideWindowInclusive returns true for pos between lo and hi', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindowInclusive(5.0), true);
    });

    test('isInsideWindowInclusive returns false for pos before lo', () {
      final page = newTestPage(
        lo: 5.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindowInclusive(2.0), false);
    });

    test('isInsideWindowInclusive returns false for pos after hi', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 5.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isInsideWindowInclusive(9.0), false);
    });

    test('isAfterWindow returns true for pos after hi', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 5.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isAfterWindow(9.0), true);
    });

    test('isAfterWindow returns false for pos at hi', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 5.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isAfterWindow(5.0), false);
    });

    test('isAfterWindow returns false for pos before hi', () {
      final page = newTestPage(
        lo: 1.0,
        hi: 9.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.isAfterWindow(5.0), false);
    });
  });

  group('ListViewPage - canExtendBeyond', () {
    test('canExtendBeyond returns true when no endBefore constraint', () {
      final page = newTestReversePage(
        lo: 1.0,
        hi: 20.0,
        endBefore: 0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.canExtendBeyond(999.0), true);
    });

    test('canExtendBeyond returns true when pos before endBefore', () {
      final page = newTestReversePage(
        lo: 1.0,
        hi: 20.0,
        endBefore: 50.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.canExtendBeyond(30.0), true);
    });

    test('canExtendBeyond returns false when pos equals endBefore', () {
      final page = newTestReversePage(
        lo: 1.0,
        hi: 20.0,
        endBefore: 50.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.canExtendBeyond(50.0), false);
    });

    test('canExtendBeyond returns false when pos after endBefore', () {
      final page = newTestReversePage(
        lo: 1.0,
        hi: 20.0,
        endBefore: 50.0,
        limit: 10,
        currentSize: 5,
      );
      expect(page.canExtendBeyond(60.0), false);
    });
  });
}
