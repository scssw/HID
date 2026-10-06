import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/singbox/model/singbox_proxy_type.dart';

part 'singbox_outbound.freezed.dart';
part 'singbox_outbound.g.dart';

@freezed
class SingboxOutboundGroup with _$SingboxOutboundGroup {
  @JsonSerializable(fieldRename: FieldRename.kebab)
  const factory SingboxOutboundGroup({
    required String tag,
    @JsonKey(fromJson: _typeFromJson) required ProxyType type,
    required String selected,
    @Default([]) List<SingboxOutboundGroupItem> items,
  }) = _SingboxOutboundGroup;

  factory SingboxOutboundGroup.fromJson(Map<String, dynamic> json) {
    try {
      final itemsRaw = json['items'];
      final items = <SingboxOutboundGroupItem>[];
      if (itemsRaw is List) {
        for (final item in itemsRaw) {
          if (item is Map<String, dynamic>) {
            try {
              items.add(SingboxOutboundGroupItem.fromJson(item));
            } catch (_) {}
          }
        }
      }
      return SingboxOutboundGroup(
        tag: (json['tag'] as String?) ?? '',
        type: _typeFromJson(json['type']),
        selected: (json['selected'] as String?) ?? '',
        items: items,
      );
    } catch (_) {
      return _$SingboxOutboundGroupFromJson(json);
    }
  }
}

@freezed
class SingboxOutboundGroupItem with _$SingboxOutboundGroupItem {
  const SingboxOutboundGroupItem._();

  @JsonSerializable(fieldRename: FieldRename.kebab)
  const factory SingboxOutboundGroupItem({
    required String tag,
    @JsonKey(fromJson: _typeFromJson) required ProxyType type,
    required int urlTestDelay,
  }) = _SingboxOutboundGroupItem;

  factory SingboxOutboundGroupItem.fromJson(Map<String, dynamic> json) {
    try {
      final delay = json['url-test-delay'];
      return SingboxOutboundGroupItem(
        tag: (json['tag'] as String?) ?? '',
        type: _typeFromJson(json['type']),
        urlTestDelay: delay is num ? delay.toInt() : 0,
      );
    } catch (_) {
      return _$SingboxOutboundGroupItemFromJson(json);
    }
  }
}

ProxyType _typeFromJson(dynamic type) => ProxyType.fromJson(type);
