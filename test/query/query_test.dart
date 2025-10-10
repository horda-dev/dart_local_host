import 'package:horda_local_host/horda_local_host.dart';
import 'package:horda_server/horda_server.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

@GenerateNiceMocks([MockSpec<MessageStore>(), MockSpec<KeyValueStore>()])
import 'query_test.mocks.dart';

void main() {
  group('query', () {
    test('should run the query', () async {
      final messageStore = MockMessageStore();
      final snapStore = MockKeyValueStore();
      final store = MemoryViewStore(messageStore, snapStore);

      void viewStub(
        String entityName,
        String actorId,
        String name,
        dynamic value,
        int version,
      ) {
        when(snapStore.containsKey('$entityName/$actorId/$name')).thenAnswer(
          (_) => Future.value(true),
        );
        when(snapStore.get('$entityName/$actorId/$name')).thenAnswer(
          (_) => Future.value(ViewSnapshot(value, version.toString())),
        );
      }

      void attrStub(
        String actorId1,
        String actorId2,
        String name,
        dynamic value,
        int version,
      ) {
        final id = CompositeId(actorId1, actorId2).id;
        when(snapStore.containsKey('$id/$name')).thenAnswer(
          (_) => Future.value(true),
        );
        when(snapStore.get('$id/$name')).thenAnswer(
          (_) => Future.value(ViewSnapshot(value, version.toString())),
        );
      }

      viewStub('TestEntity', 'actor1', 'view11', 'value11', 11);
      viewStub('TestEntity', 'actor1', 'view12', 'value12', 12);
      viewStub('TestEntity', 'actor1', 'ref1', 'actor2', 101);
      attrStub('actor1', 'actor2', 'attr1', 'a1', 1);
      attrStub('actor1', 'actor2', 'attr2', 20, 1);
      attrStub('actor1', 'actor3', 'attr3', 'a33', 1);
      attrStub('actor1', 'actor3', 'attr4', 34, 1);
      attrStub('actor1', 'actor4', 'attr3', 'a43', 1);
      attrStub('actor1', 'actor4', 'attr4', 44, 1);
      viewStub('TestEntity', 'actor1', 'list1', ['actor3', 'actor4'], 201);
      viewStub('TestEntity', 'actor2', 'view21', 'value21', 21);
      viewStub('TestEntity', 'actor2', 'view22', 'value22', 22);
      viewStub('TestEntity', 'actor3', 'view100', 'value3100', 3100);
      viewStub('TestEntity', 'actor3', 'view110', 'value3110', 3110);
      viewStub('TestEntity', 'actor4', 'view100', 'value4100', 4100);
      viewStub('TestEntity', 'actor4', 'view110', 'value4110', 4110);

      final qb = QueryDefBuilder('TestEntity')
        ..val('view11')
        ..val('view12')
        ..ref('TestEntity', 'ref1', ['attr1', 'attr2'], (qb) {
          qb
            ..val('view21')
            ..val('view22');
        })
        ..list('TestEntity', 'list1', ['attr3', 'attr4'], (qb) {
          qb
            ..val('view100')
            ..val('view110');
        });

      final res = await store.query(
        actorId: 'actor1',
        name: 'TestQuery',
        query: qb.build(),
      );

      final expectedRefAttrs = {
        'attr1': {'val': 'a1', 'chid': '1', 'type': 'String'},
        'attr2': {'val': 20, 'chid': '1', 'type': 'int'},
      };

      final expectedListAttrs = {
        (itemId: 'actor3', name: 'attr3'): {
          'val': 'a33',
          'chid': '1',
          'type': 'String',
        },
        (itemId: 'actor3', name: 'attr4'): {
          'val': 34,
          'chid': '1',
          'type': 'int',
        },
        (itemId: 'actor4', name: 'attr3'): {
          'val': 'a43',
          'chid': '1',
          'type': 'String',
        },
        (itemId: 'actor4', name: 'attr4'): {
          'val': 44,
          'chid': '1',
          'type': 'int',
        },
      };

      var expected = QueryResultBuilder()
        ..val('view11', 'value11', '11')
        ..val('view12', 'value12', '12')
        ..ref('ref1', 'actor2', expectedRefAttrs, '101', (rb) {
          rb
            ..val('view21', 'value21', '21')
            ..val('view22', 'value22', '22');
        })
        ..list('list1', expectedListAttrs, '201', (rb) {
          rb
            ..item('actor3', (rb) {
              rb
                ..val('view100', 'value3100', '3100')
                ..val('view110', 'value3110', '3110');
            })
            ..item('actor4', (rb) {
              rb
                ..val('view100', 'value4100', '4100')
                ..val('view110', 'value4110', '4110');
            });
        });

      expect(
        res.toJson(),
        expected.build().toJson(),
      );
    });
  });
}
