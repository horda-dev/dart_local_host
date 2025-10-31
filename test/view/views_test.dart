// ignore_for_file: prefer_const_constructors

import 'package:horda_server/horda_server.dart';
import 'package:test/test.dart';

// Test entity class for RefListView type parameter
class TestEntity extends Entity {
  @override
  String get name => 'TestEntity';

  @override
  void initHandlers(EntityHandlers<EntityState> handlers) {
    // noop
  }

  @override
  void initMigrations(EntityStateMigrations migrations) {
    // noop
  }
}

void main() {
  test('ref view should produce init data and changes', () async {
    var ref = RefView<TestEntity>(name: 'test-ref', value: null);
    ref.entityId = 'r1';

    // Test initValues() - returns InitViewData, not change events
    var initData = ref.initValues().first;

    expect(initData.key, 'r1');
    expect(initData.name, 'test-ref');
    expect(initData.value, null);
    expect(initData.type, 'String?');

    // Test changes() - returns Change objects directly
    ref.value = 'a1';
    var change1 = ref.changes().first;

    expect(
      change1,
      TypeMatcher<RefViewChanged>().having((e) => e.newValue, 'newValue', 'a1'),
    );

    // After getting changes, they should be cleared
    expect(ref.changes(), isEmpty);

    ref.value = null;
    var change2 = ref.changes().first;

    expect(
      change2,
      TypeMatcher<RefViewChanged>().having((e) => e.newValue, 'newValue', null),
    );

    expect(ref.changes(), isEmpty);
  });

  test('list view should produce init data and changes', () async {
    var list = RefListView<TestEntity>(name: 'test-list', value: ['a0']);
    list.entityId = 'l1';

    // Test initValues() - returns InitViewData, not change events
    var initData = list.initValues().first;

    expect(initData.key, 'l1');
    expect(initData.name, 'test-list');
    expect(initData.value, ['a0']);
    expect(initData.type, 'List<String>');

    // Test changes() - returns Change objects directly
    list.addItem('a1');
    var change1 = list.changes().first;

    expect(
      change1,
      TypeMatcher<ListViewItemAdded>().having((e) => e.itemId, 'itemId', 'a1'),
    );

    // After getting changes, they should be cleared
    expect(list.changes(), isEmpty);

    list.removeItem('a2');
    var change2 = list.changes().first;

    expect(
      change2,
      TypeMatcher<ListViewItemRemoved>().having(
        (e) => e.itemId,
        'itemId',
        'a2',
      ),
    );

    expect(list.changes(), isEmpty);
  });
}
