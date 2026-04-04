enum MutationDiffType {
  added,
  removed,
  modified;

  String get displayName => switch (this) {
    MutationDiffType.added => 'SPLICE',
    MutationDiffType.removed => 'EXCISION',
    MutationDiffType.modified => 'SHIFT',
  };
}

class MutationSeverity {
  const MutationSeverity({required this.isAmber, required this.displayLabel});
  final bool isAmber;
  final String displayLabel;

  factory MutationSeverity.fromJson(Map<String, dynamic> json) =>
      MutationSeverity(
        isAmber: json['is_amber'] as bool? ?? false,
        displayLabel: json['display_label'] as String? ?? '',
      );
}

class MutationDiff {
  const MutationDiff({
    required this.id,
    required this.type,
    required this.magnitude,
    required this.provisionIndex,
    required this.provisionTitle,
    required this.severity,
    this.oldText,
    this.newText,
    this.hasSpendingCrossover = false,
    this.spendingDisplay,
    this.isAnomaly = false,
    this.category,
  });

  final String id;
  final MutationDiffType type;
  final double magnitude;
  final int provisionIndex;
  final String provisionTitle;
  final MutationSeverity severity;
  final String? oldText;
  final String? newText;
  final bool hasSpendingCrossover;
  final String? spendingDisplay;
  final bool isAnomaly;
  final String? category;

  String get magnitudeDisplay => '${(magnitude * 100).round()}%';

  String geneLabel(int totalProvisions) =>
      'GENE-${provisionIndex.toString().padLeft(3, '0')} / $totalProvisions';

  factory MutationDiff.fromJson(Map<String, dynamic> json) => MutationDiff(
        id: json['id'] as String? ?? '',
        type: MutationDiffType.values.firstWhere(
          (e) => e.name == (json['type'] as String? ?? 'modified'),
          orElse: () => MutationDiffType.modified,
        ),
        magnitude: (json['magnitude'] as num?)?.toDouble() ?? 0.0,
        provisionIndex: json['provision_index'] as int? ?? 0,
        provisionTitle: json['provision_title'] as String? ?? '',
        severity: json['severity'] is Map<String, dynamic>
            ? MutationSeverity.fromJson(json['severity'] as Map<String, dynamic>)
            : const MutationSeverity(isAmber: false, displayLabel: ''),
        oldText: json['old_text'] as String?,
        newText: json['new_text'] as String?,
        hasSpendingCrossover: json['has_spending_crossover'] as bool? ?? false,
        spendingDisplay: json['spending_display'] as String?,
        isAnomaly: json['is_anomaly'] as bool? ?? false,
        category: json['category'] as String?,
      );
}

class BillStage {
  const BillStage({
    required this.displayName,
    required this.shortLabel,
    required this.order,
  });
  final String displayName;
  final String shortLabel;
  final int order;

  factory BillStage.fromJson(Map<String, dynamic> json) => BillStage(
        displayName: json['display_name'] as String? ?? '',
        shortLabel: json['short_label'] as String? ?? '',
        order: json['order'] as int? ?? 0,
      );
}

class BillVersion {
  const BillVersion({
    required this.id,
    required this.stage,
    required this.timestamp,
    required this.provisionCount,
  });
  final String id;
  final BillStage stage;
  final DateTime timestamp;
  final int provisionCount;

  factory BillVersion.fromJson(Map<String, dynamic> json) {
    final rawStage = json['stage'];
    final BillStage stage;
    if (rawStage is Map<String, dynamic>) {
      stage = BillStage.fromJson(rawStage);
    } else {
      final stageStr = (rawStage as String?) ?? json['stage_name'] as String? ?? '';
      stage = BillStage(
        displayName: _stageDisplayName(stageStr),
        shortLabel: _stageShortLabel(stageStr),
        order: _stageOrder(stageStr),
      );
    }
    return BillVersion(
      id: json['id'] as String? ?? '',
      stage: stage,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      provisionCount: json['provision_count'] as int? ?? 0,
    );
  }

  static String _stageDisplayName(String stage) => switch (stage.toLowerCase()) {
    'introduced' => 'Introduced',
    'committee' => 'Committee',
    'engrossed' => 'Engrossed',
    'enrolled' => 'Enrolled',
    _ => stage.isNotEmpty ? '${stage[0].toUpperCase()}${stage.substring(1)}' : '',
  };

  static String _stageShortLabel(String stage) => switch (stage.toLowerCase()) {
    'introduced' => 'INTRO',
    'committee' => 'CMTE',
    'engrossed' => 'ENGR',
    'enrolled' => 'ENRL',
    _ => stage.toUpperCase(),
  };

  static int _stageOrder(String stage) => switch (stage.toLowerCase()) {
    'introduced' => 0,
    'committee' => 1,
    'engrossed' => 2,
    'enrolled' => 3,
    _ => 99,
  };
}

class VersionComparison {
  const VersionComparison({
    required this.fromVersion,
    required this.toVersion,
    required this.diffs,
    required this.totalProvisions,
    required this.aggregateMutation,
    required this.provisionsAdded,
    required this.provisionsRemoved,
    required this.provisionsModified,
  });

  final BillVersion fromVersion;
  final BillVersion toVersion;
  final List<MutationDiff> diffs;
  final int totalProvisions;
  final double aggregateMutation;
  final int provisionsAdded;
  final int provisionsRemoved;
  final int provisionsModified;

  List<dynamic> get spotlightDiffs => [];
  int get totalMutations => 0;
  String get aggregateDisplay => '';

  bool get hasAnomalies => diffs.any((d) => d.isAnomaly);
  int get anomalyCount => diffs.where((d) => d.isAnomaly).length;

  List<MutationDiff> get diffsByMagnitude {
    final sorted = List<MutationDiff>.from(diffs);
    sorted.sort((a, b) => b.magnitude.compareTo(a.magnitude));
    return sorted;
  }

  factory VersionComparison.fromJson(Map<String, dynamic> json) =>
      VersionComparison(
        fromVersion: BillVersion.fromJson(
            json['from_version'] as Map<String, dynamic>? ?? {}),
        toVersion: BillVersion.fromJson(
            json['to_version'] as Map<String, dynamic>? ?? {}),
        diffs: (json['diffs'] as List<dynamic>?)
                ?.map((e) =>
                    MutationDiff.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        totalProvisions: json['total_provisions'] as int? ?? 0,
        aggregateMutation:
            (json['aggregate_mutation'] as num?)?.toDouble() ?? 0.0,
        provisionsAdded: json['provisions_added'] as int? ?? 0,
        provisionsRemoved: json['provisions_removed'] as int? ?? 0,
        provisionsModified: json['provisions_modified'] as int? ?? 0,
      );
}

class MutationTimeline {
  const MutationTimeline({
    required this.billId,
    required this.billTitle,
    required this.versions,
    required this.comparisons,
    this.sponsor,
    this.chamber,
    this.congressSession,
    this.billAbstract,
  });

  final String billId;
  final String billTitle;
  final String? sponsor;
  final String? chamber;
  final String? congressSession;
  final String? billAbstract;
  final List<BillVersion> versions;
  final List<VersionComparison> comparisons;

  String get shortBillId =>
      billId.length > 8 ? billId.substring(0, 8) : billId;

  VersionComparison? getComparison(String fromId, String toId) {
    try {
      return comparisons.firstWhere(
        (c) => c.fromVersion.id == fromId && c.toVersion.id == toId,
      );
    } catch (_) {
      return null;
    }
  }

  factory MutationTimeline.fromJson(Map<String, dynamic> json) =>
      MutationTimeline(
        billId: json['bill_id'] as String? ?? '',
        billTitle: json['bill_title'] as String? ?? '',
        sponsor: json['sponsor'] as String?,
        chamber: json['chamber'] as String?,
        congressSession: json['congress_session'] as String?,
        billAbstract: json['bill_abstract'] as String?,
        versions: (json['versions'] as List<dynamic>?)
                ?.map((e) =>
                    BillVersion.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        comparisons: (json['comparisons'] as List<dynamic>?)
                ?.map((e) =>
                    VersionComparison.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
