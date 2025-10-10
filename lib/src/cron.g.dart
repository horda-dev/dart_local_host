// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cron.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Cancel _$CancelFromJson(Map<String, dynamic> json) => Cancel(
      json['cancelId'] as String,
    );

Map<String, dynamic> _$CancelToJson(Cancel instance) => <String, dynamic>{
      'cancelId': instance.cancelId,
    };

Tick _$TickFromJson(Map<String, dynamic> json) => Tick(
      const DateTimeJsonConverter().fromJson((json['now'] as num).toInt()),
    );

Map<String, dynamic> _$TickToJson(Tick instance) => <String, dynamic>{
      'now': const DateTimeJsonConverter().toJson(instance.now),
    };

Scheduled _$ScheduledFromJson(Map<String, dynamic> json) => Scheduled(
      json['cancelId'] as String,
    );

Map<String, dynamic> _$ScheduledToJson(Scheduled instance) => <String, dynamic>{
      'cancelId': instance.cancelId,
    };

CronTicked _$CronTickedFromJson(Map<String, dynamic> json) => CronTicked(
      (json['sent'] as num).toInt(),
    );

Map<String, dynamic> _$CronTickedToJson(CronTicked instance) =>
    <String, dynamic>{
      'sent': instance.sent,
    };

Canceled _$CanceledFromJson(Map<String, dynamic> json) => Canceled(
      json['cancelId'] as String,
    );

Map<String, dynamic> _$CanceledToJson(Canceled instance) => <String, dynamic>{
      'cancelId': instance.cancelId,
    };
