import 'package:horda_core/horda_core.dart';

import 'list_view_page.dart';
import 'store.dart';

/// Manages list view pages within a single WebSocket session.
///
/// Each WsSession has its own ListPageManager instance to track paginated
/// list views and route change envelopes to the appropriate pages.
class ListPageManager {
  /// Page tracking by page ID.
  final _pages = <String, ListViewPage>{};

  /// Page tracking by view key.
  final _viewPages = <ViewKey, List<ListViewPage>>{};

  /// Registers a new page after a query.
  void addPage(ListViewPage page) {
    _pages[page.pageId] = page;

    _viewPages.putIfAbsent(page.viewKey, () => []).add(page);
  }

  /// Removes a specific page (client unsubscribe).
  void removePage(String pageId) {
    final page = _pages.remove(pageId);
    if (page == null) return;

    _viewPages[page.viewKey]?.remove(page);
    if (_viewPages[page.viewKey]?.isEmpty ?? false) {
      _viewPages.remove(page.viewKey);
    }
  }

  /// Checks if any pages exist for a given view.
  bool hasPagesForView(ViewKey viewKey) {
    return _viewPages.containsKey(viewKey);
  }

  /// Handles a change envelope by routing changes to affected pages.
  ///
  /// Returns a new ChangeEnvelope with the same metadata but with
  /// page-specific sync changes instead of list-level changes.
  Future<ChangeEnvelop> handleChangeEnvelope(ChangeEnvelop env) async {
    final viewKey = ViewKey(env.entityName, env.key, env.name);

    final pages = _viewPages[viewKey];
    if (pages == null || pages.isEmpty) {
      // No pages exist for this view, return the original envelope.
      return env;
    }

    // Collect all page sync changes
    final pageSyncChangesOfAllPages = <Change>[];

    for (final change in env.changes) {
      for (final page in pages) {
        final pageSyncChanges = switch (change) {
          QueryListViewItemAdded() => await page.handleItemAdded(
            change,
          ),
          QueryListViewItemRemoved() => await page.handleItemRemoved(
            change,
          ),
          ListViewCleared() => page.handleCleared(
            change,
          ),
          _ => <Change>[],
        };

        pageSyncChangesOfAllPages.addAll(pageSyncChanges);
      }
    }

    if (pageSyncChangesOfAllPages.isEmpty) {
      // No page sync changes were added, return the original envelope.
      return env;
    }

    // Return new envelope with page sync changes
    return ChangeEnvelop(
      entityName: env.entityName,
      key: env.key,
      name: env.name,
      changeId: env.changeId,
      changes: pageSyncChangesOfAllPages,
    );
  }

  void removeAllPages() {
    _pages.clear();
    _viewPages.clear();
  }
}
