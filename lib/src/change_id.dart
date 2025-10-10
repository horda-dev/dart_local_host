import 'package:horda_core/horda_core.dart';

class ChangeIdTracker {
  String incrementForView({
    required String entityName,
    required String entityId,
    required String viewName,
  }) {
    final key = '$entityName/$entityId/$viewName';
    final newValue = (_changeIDs[key] ?? 0) + 1;
    _changeIDs[key] = newValue;
    return '0:$newValue:0:0';
  }

  String incrementForAttribute({
    required String entityId1,
    required String entityId2,
    required String attrName,
  }) {
    final key = '${CompositeId(entityId1, entityId2).id}/$attrName';
    final newValue = (_changeIDs[key] ?? 0) + 1;
    _changeIDs[key] = newValue;
    return '0:$newValue:0:0';
  }

  void removeView({
    required String entityName,
    required String entityId,
    required String viewName,
  }) {
    final key = '$entityName/$entityId/$viewName';
    _changeIDs.remove(key);
  }

  void removeAttribute({
    required String entityId1,
    required String entityId2,
    required String attrName,
  }) {
    final key = '$entityId1-$entityId2/$attrName';
    _changeIDs.remove(key);
  }

  /// Key is view or attribute key, value is latest change id.
  final _changeIDs = <String, int>{};
}
