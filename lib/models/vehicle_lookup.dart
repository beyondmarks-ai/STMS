class VehicleCreditWallet {
  const VehicleCreditWallet({
    required this.balance,
    required this.initialCredits,
    required this.lookupCost,
    required this.provider,
    required this.configured,
  });

  final int balance;
  final int initialCredits;
  final int lookupCost;
  final String provider;
  final bool configured;

  factory VehicleCreditWallet.fromJson(Map<String, dynamic> json) =>
      VehicleCreditWallet(
        balance: json['balance'] as int? ?? 0,
        initialCredits: json['initialCredits'] as int? ?? 100,
        lookupCost: json['lookupCost'] as int? ?? 1,
        provider: json['provider'] as String? ?? 'DataFlag',
        configured: json['configured'] as bool? ?? false,
      );

  VehicleCreditWallet copyWith({int? balance}) => VehicleCreditWallet(
    balance: balance ?? this.balance,
    initialCredits: initialCredits,
    lookupCost: lookupCost,
    provider: provider,
    configured: configured,
  );
}

class VehicleCreditLedgerEntry {
  const VehicleCreditLedgerEntry({
    required this.id,
    required this.amount,
    required this.balanceAfter,
    required this.reason,
    required this.createdAt,
    this.vehicleNumber,
    this.provider,
  });

  final String id;
  final int amount;
  final int balanceAfter;
  final String reason;
  final String? vehicleNumber;
  final String? provider;
  final DateTime createdAt;

  factory VehicleCreditLedgerEntry.fromJson(Map<String, dynamic> json) =>
      VehicleCreditLedgerEntry(
        id: json['id'] as String,
        amount: json['amount'] as int,
        balanceAfter: json['balanceAfter'] as int,
        reason: json['reason'] as String,
        vehicleNumber: json['vehicleNumber'] as String?,
        provider: json['provider'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class VehicleLookupResult {
  const VehicleLookupResult({
    required this.lookupId,
    required this.vehicleNumber,
    required this.provider,
    required this.creditsRemaining,
    required this.details,
    required this.checkedAt,
  });

  final String lookupId;
  final String vehicleNumber;
  final String provider;
  final int creditsRemaining;
  final Map<String, dynamic> details;
  final DateTime checkedAt;

  factory VehicleLookupResult.fromJson(Map<String, dynamic> json) =>
      VehicleLookupResult(
        lookupId: json['lookupId'] as String,
        vehicleNumber: json['vehicleNumber'] as String,
        provider: json['provider'] as String? ?? 'DataFlag',
        creditsRemaining: json['creditsRemaining'] as int,
        details: Map<String, dynamic>.from(json['details'] as Map),
        checkedAt: DateTime.parse(json['checkedAt'] as String),
      );
}
