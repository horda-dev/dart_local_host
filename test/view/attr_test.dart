// ignore_for_file: prefer_const_constructors

import 'package:horda_server/horda_server.dart';
import 'package:test/test.dart';

// Test entity class for RefView type parameter
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
  group('RefView attributes', () {
    test('should produce init data and attribute change events', () async {
      var ref = RefView<TestEntity>(name: 'test-ref', value: 'r2');
      ref.entityId = 'r1';

      // Test initValues() - returns only InitViewData for the ref itself
      // Attributes are NOT included in initValues(), they're created on-the-fly
      var initData = ref.initValues().first;

      expect(initData.key, 'r1');
      expect(initData.name, 'test-ref');
      expect(initData.value, 'r2');
      expect(initData.type, 'String?');

      // Modify attributes - they're created when first set
      // valueAttr requires the attrId (ref value) as first parameter
      ref.valueAttr<String>('r2', 'attr1').value = 'a1';
      ref.valueAttr<String>('r2', 'attr2').value = 'a2';

      var changes = ref.changes();

      // Should return 2 RefValueAttributeChanged objects
      expect(changes.length, 2);

      var changeList = changes.toList();
      expect(
        changeList[0],
        TypeMatcher<RefValueAttributeChanged>()
            .having((e) => e.attrName, 'attrName', 'attr1')
            .having((e) => e.newValue, 'newValue', 'a1'),
      );
      expect(
        changeList[1],
        TypeMatcher<RefValueAttributeChanged>()
            .having((e) => e.attrName, 'attrName', 'attr2')
            .having((e) => e.newValue, 'newValue', 'a2'),
      );

      // After getting changes, they should be cleared
      expect(ref.changes(), isEmpty);

      // Change attribute values again
      ref.valueAttr<String>('r2', 'attr1').value = 'a11';
      ref.valueAttr<String>('r2', 'attr2').value = 'a21';
      var changes2 = ref.changes();

      expect(changes2.length, 2);
      var changeList2 = changes2.toList();
      expect(
        changeList2[0],
        TypeMatcher<RefValueAttributeChanged>()
            .having((e) => e.attrName, 'attrName', 'attr1')
            .having((e) => e.newValue, 'newValue', 'a11'),
      );
      expect(
        changeList2[1],
        TypeMatcher<RefValueAttributeChanged>()
            .having((e) => e.attrName, 'attrName', 'attr2')
            .having((e) => e.newValue, 'newValue', 'a21'),
      );
    });

    test('null ref view attributes work correctly', () async {
      var ref = RefView<TestEntity>(name: 'test-ref', value: null);
      ref.entityId = 'r1';

      // With null ref value, we can't meaningfully set attributes
      // because there's no entity to attach them to
      // The API doesn't prevent it, but it's semantically meaningless

      var initData = ref.initValues().first;
      expect(initData.value, null);
      expect(initData.type, 'String?');
    });

    test('changing both ref value and attributes produces correct changes',
        () async {
      var ref = RefView<TestEntity>(name: 'test-ref', value: 'r2');
      ref.entityId = 'r1';

      // Change the ref value AND set attributes
      ref.value = 'r3';
      ref.valueAttr<String>('r3', 'attr1').value = 'a11';
      ref.valueAttr<String>('r3', 'attr2').value = 'a21';

      var changes = ref.changes();

      // Should return RefViewChanged + 2 RefValueAttributeChanged
      expect(changes.length, 3);

      var changeList = changes.toList();

      // First change should be RefViewChanged
      expect(
        changeList[0],
        TypeMatcher<RefViewChanged>()
            .having((e) => e.newValue, 'newValue', 'r3'),
      );

      // Next two should be attribute changes
      expect(
        changeList[1],
        TypeMatcher<RefValueAttributeChanged>()
            .having((e) => e.attrName, 'attrName', 'attr1')
            .having((e) => e.newValue, 'newValue', 'a11'),
      );
      expect(
        changeList[2],
        TypeMatcher<RefValueAttributeChanged>()
            .having((e) => e.attrName, 'attrName', 'attr2')
            .having((e) => e.newValue, 'newValue', 'a21'),
      );
    });
  });
}
