class CustomDomainRule {
  const CustomDomainRule({
    required this.domain,
    required this.outbound,
    required this.updatedAt,
  });

  final String domain;
  final String outbound; // 'proxy' or 'bypass'
  final DateTime updatedAt;

  bool get isDirect => outbound == 'bypass';
  bool get isProxy => outbound == 'proxy';

  CustomDomainRule copyWith({
    String? domain,
    String? outbound,
    DateTime? updatedAt,
  }) {
    return CustomDomainRule(
      domain: domain ?? this.domain,
      outbound: outbound ?? this.outbound,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'domain': domain,
        'outbound': outbound,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CustomDomainRule.fromJson(Map<String, dynamic> json) =>
      CustomDomainRule(
        domain: json['domain'] as String? ?? '',
        outbound: json['outbound'] as String? ?? 'proxy',
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomDomainRule &&
          runtimeType == other.runtimeType &&
          domain == other.domain &&
          outbound == other.outbound;

  @override
  int get hashCode => domain.hashCode ^ outbound.hashCode;
}
