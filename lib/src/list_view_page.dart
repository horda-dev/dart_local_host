import 'package:horda_core/horda_core.dart';

import 'store.dart';

/// Represents a paginated window into a list view.
///
/// A page tracks a specific window of items within a list view, maintaining
/// boundaries (lo/hi) and responding to list-level changes by generating
/// page-specific sync changes for clients.
class ListViewPage {
  /// Creates a list view page with the specified parameters.
  ListViewPage({
    required this.pageId,
    required this.startAfter,
    required this.endBefore,
    required this.lo,
    required this.hi,
    required this.limit,
    required this.currentSize,
    required this.viewKey,
    required this.viewStore,
  });

  /// Unique identifier for this page.
  final String pageId;

  /// Query parameter: lower boundary (exclusive).
  /// Use 0 as sentinel for "no lower boundary".
  final double startAfter;

  /// Query parameter: upper boundary (exclusive).
  /// Use 0 as sentinel for "no upper boundary".
  final double endBefore;

  /// Current window lower bound (inclusive).
  double lo;

  /// Current window upper bound (inclusive).
  double hi;

  /// Maximum number of items in the page.
  /// Positive = forward pagination, negative = reverse pagination.
  final int limit;

  /// Current number of items in the window.
  int currentSize;

  /// View key identifying the view (entityName, entityId, viewName).
  final ViewKey viewKey;

  /// View store for querying list items.
  final ViewStore viewStore;

  /// Returns true if this is a forward pagination page.
  bool get isForward => limit > 0;

  /// Returns true if this is a reverse pagination page.
  bool get isReverse => limit < 0;

  /// Returns the maximum size of this page.
  int get maxSize => limit.abs();

  /// Returns true if the page is empty.
  bool get isEmpty => currentSize == 0;

  /// Returns true if the page is full.
  bool get isFull => currentSize >= maxSize;

  /// Checks if a position is inside the window (exclusive of boundaries).
  bool isInsideWindow(double pos) => pos > lo && pos < hi;

  /// Checks if a position is inside the window (inclusive of boundaries).
  bool isInsideWindowInclusive(double pos) => pos >= lo && pos <= hi;

  /// Checks if a position is after the window (greater than hi).
  bool isAfterWindow(double pos) => pos > hi;

  /// Checks if the window can extend (not full).
  bool canExtendWindow() => currentSize < maxSize;

  /// Checks if the position is within query boundaries (can extend beyond current window).
  bool canExtendBeyond(double pos) {
    if (endBefore != 0 && pos >= endBefore) {
      return false;
    }
    return true;
  }

  /// Handles a list item addition and returns page-specific sync changes.
  ///
  /// Returns empty list if this page is not affected by the change.
  /// Returns [ListPageItemAdded] changes if the page is affected.
  /// May return push-out changes (removal + addition) for reverse pages.
  Future<List<Change>> handleItemAdded(QueryListViewItemAdded change) async {
    final pos = change.pos;
    final refId = change.refId;

    // Scenario 1: Not affected at all
    if (!_isAffectedByAdd(pos)) {
      return [];
    }

    // Scenario 2: Push-out (full reverse page with item after window)
    if (isFull && isReverse && isAfterWindow(pos)) {
      return _handlePushout(pos, refId);
    }

    // Scenario 3: Normal add (inside window or after window with space)
    _adjustItemAdded(pos);
    return [
      ListPageItemAdded(
        pageId: pageId,
        pos: pos,
        refId: refId,
      ),
    ];
  }

  /// Handles a list item removal and returns page-specific sync changes.
  ///
  /// Returns empty list if this page is not affected by the change.
  /// Returns [ListPageItemRemoved] if the item is in the window.
  /// May also return [ListPageItemAdded] for backfill items.
  Future<List<Change>> handleItemRemoved(
    QueryListViewItemRemoved change,
  ) async {
    final pos = change.pos;

    // Check if the position is in the window (inclusive)
    if (!isInsideWindowInclusive(pos)) {
      return [];
    }

    final changes = <Change>[
      ListPageItemRemoved(
        pageId: pageId,
        pos: pos,
      ),
    ];

    // Query for backfill item
    final backfillItem = isReverse
        ? await viewStore.getPreviousListItem(
            viewKey.entityName,
            viewKey.entityId,
            viewKey.viewName,
            lo,
          )
        : await viewStore.getNextListItem(
            viewKey.entityName,
            viewKey.entityId,
            viewKey.viewName,
            hi,
          );

    if (backfillItem != null) {
      // Add backfill item
      changes.add(
        ListPageItemAdded(
          pageId: pageId,
          pos: backfillItem.position,
          refId: backfillItem.refId,
        ),
      );
      _adjustItemRemovedWithBackfill(backfillItem.position);
    } else {
      // No backfill available
      _adjustItemRemovedWithoutBackfill();
    }

    return changes;
  }

  /// Handles list cleared and returns page-specific sync changes.
  ///
  /// Always returns [ListPageCleared] since clearing affects all pages.
  List<Change> handleCleared(ListViewCleared change) {
    _adjustCleared();
    return [
      ListPageCleared(
        pageId: pageId,
      ),
    ];
  }

  // State adjustment methods (internal helpers)

  /// Adjusts page state when an item is added.
  void _adjustItemAdded(double pos) {
    // Inside window, can extend
    if (isInsideWindow(pos) && canExtendWindow()) {
      currentSize++;
      return;
    }

    // Inside window, full (mid-list insertion - not yet supported)
    if (isInsideWindow(pos) && !canExtendWindow()) {
      return;
    }

    // After window, can extend
    if (isAfterWindow(pos) && canExtendWindow()) {
      hi = pos;
      currentSize++;
    }
  }

  /// Adjusts page boundaries after a push-out (reverse page sliding forward).
  void _adjustPushout(double newLo, double newHi) {
    lo = newLo;
    hi = newHi;
    // currentSize unchanged (still full)
  }

  /// Adjusts page state when an item is removed without backfill.
  void _adjustItemRemovedWithoutBackfill() {
    if (!isEmpty) currentSize--;
  }

  /// Adjusts page state when an item is removed with backfill.
  void _adjustItemRemovedWithBackfill(double backfillPos) {
    if (isReverse) {
      lo = backfillPos;
    } else {
      hi = backfillPos;
    }
    // currentSize unchanged (backfill maintains size)
  }

  /// Adjusts page state when the list is cleared.
  void _adjustCleared() {
    currentSize = 0;
    // lo/hi preserved to maintain window position
  }

  /// Checks if an item addition affects this page.
  bool _isAffectedByAdd(double pos) {
    // Inside window - always affected
    if (isInsideWindow(pos)) return true;

    // After window - affected if can extend OR push-out scenario
    if (isAfterWindow(pos)) {
      return (isForward && canExtendWindow()) ||
          (isReverse && canExtendBeyond(pos));
    }

    return false;
  }

  /// Handles push-out scenario for full reverse pages.
  ///
  /// When a full reverse page receives an item after the window,
  /// the first item is pushed out and the new item is added at the end.
  Future<List<Change>> _handlePushout(double pos, String refId) async {
    final oldLo = lo;

    final nextItem = await viewStore.getNextListItem(
      viewKey.entityName,
      viewKey.entityId,
      viewKey.viewName,
      oldLo,
    );

    if (nextItem == null) {
      // No next item found (shouldn't happen in normal cases)
      return [];
    }

    _adjustPushout(nextItem.position, pos);

    return [
      ListPageItemRemoved(
        pageId: pageId,
        pos: oldLo,
      ),
      ListPageItemAdded(
        pageId: pageId,
        pos: pos,
        refId: refId,
      ),
    ];
  }
}
