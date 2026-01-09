// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:horda_local_host/horda_local_host.dart';
import 'package:horda_server/horda_server.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryViewStore change projection', () {
    late MemKeyValueStore snapStore;
    late MemoryViewStore viewStore;
    late StreamController<ChangeEnvelop> changeStream;

    setUp(() {
      snapStore = MemKeyValueStore();
      viewStore = MemoryViewStore(snapStore);
      changeStream = StreamController<ChangeEnvelop>();

      viewStore.startProjectingChanges(changeStream.stream);
    });

    tearDown(() {
      changeStream.close();
      viewStore.stopProjectingChanges();
    });

    group('ValueView changes', () {
      test('ValueViewChanged projects correctly', () async {
        await snapStore.set(
          'TestEntity/actor1/view1',
          ViewSnapshot('oldValue', '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'view1',
          changeId: '1',
          changes: [ValueViewChanged<String>('newValue')],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'view1',
        );
        expect(snapshot.value, 'newValue');
        expect(snapshot.changeId, '1');
      });

      test('ValueViewChanged with multiple changes uses only last', () async {
        await snapStore.set(
          'TestEntity/actor1/view1',
          ViewSnapshot('initial', '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'view1',
          changeId: '1',
          changes: [
            ValueViewChanged<String>('first'),
            ValueViewChanged<String>('second'),
            ValueViewChanged<String>('third'),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'view1',
        );
        expect(snapshot.value, 'third');
        expect(snapshot.changeId, '1');
      });
    });

    group('CounterView changes', () {
      test('CounterViewIncremented projects correctly', () async {
        await snapStore.set(
          'TestEntity/actor1/counter1',
          ViewSnapshot(10, '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'counter1',
          changeId: '1',
          changes: [CounterViewIncremented(by: 5)],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'counter1',
        );
        expect(snapshot.value, 15);
        expect(snapshot.changeId, '1');
      });

      test('CounterViewDecremented projects correctly', () async {
        await snapStore.set(
          'TestEntity/actor1/counter1',
          ViewSnapshot(20, '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'counter1',
          changeId: '1',
          changes: [CounterViewDecremented(by: 7)],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'counter1',
        );
        expect(snapshot.value, 13);
        expect(snapshot.changeId, '1');
      });

      test('CounterViewReset projects correctly', () async {
        await snapStore.set(
          'TestEntity/actor1/counter1',
          ViewSnapshot(100, '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'counter1',
          changeId: '1',
          changes: [CounterViewReset(newValue: 42)],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'counter1',
        );
        expect(snapshot.value, 42);
        expect(snapshot.changeId, '1');
      });

      test('Multiple counter operations accumulate', () async {
        await snapStore.set(
          'TestEntity/actor1/counter1',
          ViewSnapshot(10, '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'counter1',
          changeId: '1',
          changes: [
            CounterViewIncremented(by: 5),
            CounterViewIncremented(by: 3),
            CounterViewDecremented(by: 2),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'counter1',
        );
        expect(snapshot.value, 16); // 10 + 5 + 3 - 2
        expect(snapshot.changeId, '1');
      });
    });

    group('RefView changes', () {
      test('RefViewChanged projects correctly', () async {
        await snapStore.set(
          'TestEntity/actor1/ref1',
          ViewSnapshot('actor2', '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'ref1',
          changeId: '1',
          changes: [RefViewChanged('actor3')],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'ref1',
        );
        expect(snapshot.value, 'actor3');
        expect(snapshot.changeId, '1');
      });

      test('RefViewChanged to null projects correctly', () async {
        await snapStore.set(
          'TestEntity/actor1/ref1',
          ViewSnapshot('actor2', '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'ref1',
          changeId: '1',
          changes: [RefViewChanged(null)],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'ref1',
        );
        expect(snapshot.value, null);
        expect(snapshot.changeId, '1');
      });

      test('RefViewChanged with multiple changes uses only last', () async {
        await snapStore.set(
          'TestEntity/actor1/ref1',
          ViewSnapshot('initial', '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'ref1',
          changeId: '1',
          changes: [
            RefViewChanged('actor2'),
            RefViewChanged('actor3'),
            RefViewChanged('actor4'),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'ref1',
        );
        expect(snapshot.value, 'actor4');
        expect(snapshot.changeId, '1');
      });
    });

    group('ListView changes', () {
      test('ListViewItemAdded projects correctly', () async {
        await snapStore.set(
          'TestEntity/actor1/list1',
          ViewSnapshot([
            ListItem('key1', 'actor2'),
          ], '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'list1',
          changeId: '1',
          changes: [ListViewItemAdded('key2', 'actor3')],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'list1',
        );
        final list = snapshot.value as List<ListItem>;
        expect(list.length, 2);
        expect(list[0].key, 'key1');
        expect(list[0].value, 'actor2');
        expect(list[1].key, 'key2');
        expect(list[1].value, 'actor3');
        expect(snapshot.changeId, '1');
      });

      test('ListViewItemAddedIfAbsent adds when not present', () async {
        await snapStore.set(
          'TestEntity/actor1/list1',
          ViewSnapshot([
            ListItem('key1', 'actor2'),
          ], '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'list1',
          changeId: '1',
          changes: [ListViewItemAddedIfAbsent('key2', 'actor3')],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'list1',
        );
        final list = snapshot.value as List<ListItem>;
        expect(list.length, 2);
        expect(list[1].value, 'actor3');
      });

      test('ListViewItemAddedIfAbsent does not add duplicate', () async {
        await snapStore.set(
          'TestEntity/actor1/list1',
          ViewSnapshot([
            ListItem('key1', 'actor2'),
            ListItem('key2', 'actor3'),
          ], '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'list1',
          changeId: '1',
          changes: [ListViewItemAddedIfAbsent('key3', 'actor3')],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'list1',
        );
        final list = snapshot.value as List<ListItem>;
        expect(list.length, 2); // Should not add duplicate
      });

      test('ListViewItemRemoved projects correctly', () async {
        await snapStore.set(
          'TestEntity/actor1/list1',
          ViewSnapshot([
            ListItem('key1', 'actor2'),
            ListItem('key2', 'actor3'),
            ListItem('key3', 'actor4'),
          ], '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'list1',
          changeId: '1',
          changes: [ListViewItemRemoved('key2')],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'list1',
        );
        final list = snapshot.value as List<ListItem>;
        expect(list.length, 2);
        expect(list[0].key, 'key1');
        expect(list[1].key, 'key3');
      });

      test('ListViewCleared projects correctly', () async {
        await snapStore.set(
          'TestEntity/actor1/list1',
          ViewSnapshot([
            ListItem('key1', 'actor2'),
            ListItem('key2', 'actor3'),
          ], '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'list1',
          changeId: '1',
          changes: [ListViewCleared()],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'list1',
        );
        final list = snapshot.value as List<ListItem>;
        expect(list.length, 0);
        expect(snapshot.changeId, '1');
      });

      test('Multiple list operations accumulate in order', () async {
        await snapStore.set(
          'TestEntity/actor1/list1',
          ViewSnapshot([
            ListItem('key1', 'actor2'),
          ], '0'),
        );

        final change = ChangeEnvelop(
          entityName: 'TestEntity',
          key: 'actor1',
          name: 'list1',
          changeId: '1',
          changes: [
            ListViewItemAdded('key2', 'actor3'),
            ListViewItemAdded('key3', 'actor4'),
            ListViewItemRemoved('key1'),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.viewSnapshot(
          'TestEntity',
          'actor1',
          'list1',
        );
        final list = snapshot.value as List<ListItem>;
        expect(list.length, 2);
        expect(list[0].key, 'key2');
        expect(list[0].value, 'actor3');
        expect(list[1].key, 'key3');
        expect(list[1].value, 'actor4');
      });
    });

    group('Value attribute changes', () {
      test('RefValueAttributeChanged projects correctly with existing value',
          () async {
        final cid = CompositeId('actor1', 'actor2').id;
        await snapStore.set(
          '$cid/attr1',
          ViewSnapshot('oldValue', '0'),
        );

        final change = ChangeEnvelop(
          entityName: '', // Empty for attributes
          key: cid,
          name: 'attr1',
          changeId: '1',
          changes: [
            RefValueAttributeChanged(
              attrId: 'actor2',
              attrName: 'attr1',
              newValue: 'newValue',
            ),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.attributeSnapshot(
          'actor1',
          'actor2',
          'attr1',
        );
        expect(snapshot.value, 'newValue');
        expect(snapshot.changeId, '1');
      });

      test('RefValueAttributeChanged projects correctly with null initial value',
          () async {
        final cid = CompositeId('actor1', 'actor2').id;
        // Don't set initial snapshot - attribute doesn't exist yet

        final change = ChangeEnvelop(
          entityName: '', // Empty for attributes
          key: cid,
          name: 'attr1',
          changeId: '1',
          changes: [
            RefValueAttributeChanged(
              attrId: 'actor2',
              attrName: 'attr1',
              newValue: 'firstValue',
            ),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.attributeSnapshot(
          'actor1',
          'actor2',
          'attr1',
        );
        expect(snapshot.value, 'firstValue');
        expect(snapshot.changeId, '1');
      });

      test('RefValueAttributeChanged with multiple changes uses only last',
          () async {
        final cid = CompositeId('actor1', 'actor2').id;
        await snapStore.set(
          '$cid/attr1',
          ViewSnapshot('initial', '0'),
        );

        final change = ChangeEnvelop(
          entityName: '',
          key: cid,
          name: 'attr1',
          changeId: '1',
          changes: [
            RefValueAttributeChanged(
              attrId: 'actor2',
              attrName: 'attr1',
              newValue: 'first',
            ),
            RefValueAttributeChanged(
              attrId: 'actor2',
              attrName: 'attr1',
              newValue: 'second',
            ),
            RefValueAttributeChanged(
              attrId: 'actor2',
              attrName: 'attr1',
              newValue: 'third',
            ),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.attributeSnapshot(
          'actor1',
          'actor2',
          'attr1',
        );
        expect(snapshot.value, 'third');
        expect(snapshot.changeId, '1');
      });
    });

    group('Counter attribute changes', () {
      test('CounterAttrIncremented projects correctly with existing value',
          () async {
        final cid = CompositeId('actor1', 'actor2').id;
        await snapStore.set(
          '$cid/counter1',
          ViewSnapshot(10, '0'),
        );

        final change = ChangeEnvelop(
          entityName: '',
          key: cid,
          name: 'counter1',
          changeId: '1',
          changes: [
            CounterAttrIncremented(
              attrId: 'actor2',
              attrName: 'counter1',
              by: 5,
            ),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.attributeSnapshot(
          'actor1',
          'actor2',
          'counter1',
        );
        expect(snapshot.value, 15);
        expect(snapshot.changeId, '1');
      });

      test('CounterAttrIncremented projects correctly with null initial value',
          () async {
        final cid = CompositeId('actor1', 'actor2').id;
        // Don't set initial snapshot - test ?? 0 operator

        final change = ChangeEnvelop(
          entityName: '',
          key: cid,
          name: 'counter1',
          changeId: '1',
          changes: [
            CounterAttrIncremented(
              attrId: 'actor2',
              attrName: 'counter1',
              by: 5,
            ),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.attributeSnapshot(
          'actor1',
          'actor2',
          'counter1',
        );
        expect(snapshot.value, 5); // null + 5 = 0 + 5 = 5
        expect(snapshot.changeId, '1');
      });

      test('CounterAttrDecremented projects correctly', () async {
        final cid = CompositeId('actor1', 'actor2').id;
        await snapStore.set(
          '$cid/counter1',
          ViewSnapshot(20, '0'),
        );

        final change = ChangeEnvelop(
          entityName: '',
          key: cid,
          name: 'counter1',
          changeId: '1',
          changes: [
            CounterAttrDecremented(
              attrId: 'actor2',
              attrName: 'counter1',
              by: 7,
            ),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.attributeSnapshot(
          'actor1',
          'actor2',
          'counter1',
        );
        expect(snapshot.value, 13);
        expect(snapshot.changeId, '1');
      });

      test('CounterAttrDecremented with null initial value', () async {
        final cid = CompositeId('actor1', 'actor2').id;
        // Don't set initial snapshot

        final change = ChangeEnvelop(
          entityName: '',
          key: cid,
          name: 'counter1',
          changeId: '1',
          changes: [
            CounterAttrDecremented(
              attrId: 'actor2',
              attrName: 'counter1',
              by: 3,
            ),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.attributeSnapshot(
          'actor1',
          'actor2',
          'counter1',
        );
        expect(snapshot.value, -3); // null - 3 = 0 - 3 = -3
        expect(snapshot.changeId, '1');
      });

      test('CounterAttrReset projects correctly', () async {
        final cid = CompositeId('actor1', 'actor2').id;
        await snapStore.set(
          '$cid/counter1',
          ViewSnapshot(100, '0'),
        );

        final change = ChangeEnvelop(
          entityName: '',
          key: cid,
          name: 'counter1',
          changeId: '1',
          changes: [
            CounterAttrReset(
              attrId: 'actor2',
              attrName: 'counter1',
              newValue: 42,
            ),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.attributeSnapshot(
          'actor1',
          'actor2',
          'counter1',
        );
        expect(snapshot.value, 42);
        expect(snapshot.changeId, '1');
      });

      test('Multiple counter attribute operations accumulate', () async {
        final cid = CompositeId('actor1', 'actor2').id;
        await snapStore.set(
          '$cid/counter1',
          ViewSnapshot(10, '0'),
        );

        final change = ChangeEnvelop(
          entityName: '',
          key: cid,
          name: 'counter1',
          changeId: '1',
          changes: [
            CounterAttrIncremented(
              attrId: 'actor2',
              attrName: 'counter1',
              by: 5,
            ),
            CounterAttrIncremented(
              attrId: 'actor2',
              attrName: 'counter1',
              by: 3,
            ),
            CounterAttrDecremented(
              attrId: 'actor2',
              attrName: 'counter1',
              by: 2,
            ),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.attributeSnapshot(
          'actor1',
          'actor2',
          'counter1',
        );
        expect(snapshot.value, 16); // 10 + 5 + 3 - 2
        expect(snapshot.changeId, '1');
      });

      test('Multiple counter attribute operations with null initial value',
          () async {
        final cid = CompositeId('actor1', 'actor2').id;
        // Don't set initial snapshot

        final change = ChangeEnvelop(
          entityName: '',
          key: cid,
          name: 'counter1',
          changeId: '1',
          changes: [
            CounterAttrIncremented(
              attrId: 'actor2',
              attrName: 'counter1',
              by: 10,
            ),
            CounterAttrIncremented(
              attrId: 'actor2',
              attrName: 'counter1',
              by: 5,
            ),
            CounterAttrDecremented(
              attrId: 'actor2',
              attrName: 'counter1',
              by: 3,
            ),
          ],
        );

        changeStream.add(change);
        await Future.delayed(Duration(milliseconds: 10));

        final snapshot = await viewStore.attributeSnapshot(
          'actor1',
          'actor2',
          'counter1',
        );
        expect(snapshot.value, 12); // 0 + 10 + 5 - 3
        expect(snapshot.changeId, '1');
      });
    });
  });
}
