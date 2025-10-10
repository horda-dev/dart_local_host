extension LengthLimitedString on Map {
  /// Applies a string length limit on each key and value of a map entry.
  ///
  /// Useful when logging a Map with large contents, like encoded files, etc.
  String toLimitedString([int limit = 128]) {
    var str = '{';

    for (var i = 0; i < entries.length; i++) {
      final entry = entries.elementAt(i);
      final key = limitString(entry.key);
      final value = limitString(entry.value);

      str += '$key: $value';

      final isNotLast = (i < entries.length - 1);
      if (isNotLast) {
        str += ', ';
      }
    }

    str += '}';

    return str;
  }
}

String limitString(Object? object, [int limit = 128]) {
  final str = object.toString();

  if (str.length > limit) {
    final shortened = str.substring(0, limit - 3);
    return '$shortened...';
  }

  return str;
}
