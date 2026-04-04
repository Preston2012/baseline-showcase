/// Figure model for Baseline.
///
/// Represents a public figure tracked by the app. Parsed from the
/// `figures` table via PostgREST (not an Edge Function - see Data
/// Access Doctrine).
///
/// Role, party, state, and photoUrl are extracted from the `metadata`
/// JSONB column. These vary by figure category:
/// - US_POLITICS: title, party, state, chamber, district, bioguide_id
/// - AI_TECH / CRYPTO / MEDIA_CULTURE: title only
/// - OFFICE: title, chamber (if applicable)
///
/// Photo URLs point to Supabase Storage. F3.16 (Image Service) handles
/// URL construction, caching, and fallback silhouette. This model just
/// stores the raw URL if present in metadata.
///
/// Categories (locked - matches A1 CHECK constraint):
/// - US_POLITICS
/// - GLOBAL_POLITICS
/// - AI_TECH
/// - FINANCE
/// - CRYPTO
/// - MEDIA_CULTURE
/// - CENTRAL_BANK
///
/// All parsed DateTimes are normalized to UTC via .toUtc().
///
/// Metadata getters use `is String` type checks (not `as String?`)
/// to prevent TypeError if a metadata value is an unexpected type
/// (e.g. int, bool, nested Map).
///
/// Path: lib/models/figure.dart
class Figure {
const Figure({
required this.figureId,
required this.name,
required this.category,
required this.isActive,
this.activationOrder,
this.metadata,
this.photoUrlDirect,
required this.createdAt,
});
final String figureId;
/// Display name (e.g., "Donald Trump", "Sam Altman").
final String name;
/// Category for grouping in the Figures Tab.
/// One of: US_POLITICS, GLOBAL_POLITICS, AI_TECH, FINANCE,
/// CRYPTO, MEDIA_CULTURE, CENTRAL_BANK.
final String category;
/// Whether this figure is currently tracked (active pipeline).
final bool isActive;
/// Sort order within the Figures Tab. Null = appended at end.
final int? activationOrder;
/// Raw metadata JSONB. Contains role/title, party, state,
/// bioguide_id, etc. Shape varies by category.
final Map<String, dynamic>? metadata;
/// Top-level photo_url column from the figures table.
final String? photoUrlDirect;
/// When this figure was first added.
final DateTime createdAt;

  /// Alias for figureId
  String get id => figureId;
  /// Alias for name
  String get displayName => name;
  /// Alias for photoUrl
  String? get imageUrl => photoUrl;
  /// Party + state label
  String? get partyState {
    final p = party;
    final s = state;
    if (p == null && s == null) return null;
    if (s != null) return '${p ?? ""}-$s';
    return p;
  }
// ── Metadata convenience getters ─────────────────────────────────
//
// All getters use `is String` checks instead of `as String?` to
// prevent TypeError when metadata contains unexpected types.
/// Role/title (e.g., "45th & 47th President", "U.S. Senator").
/// Checks top-level 'title' first (flattened views), then metadata['title'].
/// Null if neither is set.
String? get role {
final topLevel = metadata?['title'];
if (topLevel is String && topLevel.isNotEmpty) return topLevel;
return null;
}
/// Political party (e.g., "R", "D", "I"). Null for non-political.
String? get party {
final v = metadata?['party'];
return v is String ? v : null;
}
/// State abbreviation (e.g., "CA", "TX"). Null for non-Congress.
String? get state {
final v = metadata?['state'];
return v is String ? v : null;
}
/// Congressional chamber (e.g., "HOUSE", "SENATE"). Null for non-Congress.
String? get chamber {
final v = metadata?['chamber'];
return v is String ? v : null;
}
/// Congressional district (e.g., "14"). Null for senators / non-Congress.
String? get district {
final v = metadata?['district'];
return v is String ? v : null;
}
/// Bioguide ID for Congress members. Null for non-Congress.
String? get bioguideId {
final v = metadata?['bioguide_id'];
return v is String ? v : null;
}
/// Photo URL. Checks top-level column first, then metadata fallback.
/// F3.16 (Image Service) handles fallback silhouette when null.
String? get photoUrl {
if (photoUrlDirect != null && photoUrlDirect!.isNotEmpty) return photoUrlDirect;
final v = metadata?['photo_url'];
return v is String ? v : null;
}
/// Formatted role + party string for display (e.g., "U.S. Senator · D-CA").
/// Uses middle dot (·) separator, matches F2.10 FigureRow visual pattern.
/// Returns just role if no party, or null if neither.
String? get rolePartyLabel {
final r = role;
final p = party;
final s = state;
if (r == null && p == null) return null;
if (p == null) return r;
if (r == null) {
return s != null ? '$p-$s' : p;
}
return s != null ? '$r · $p-$s' : '$r · $p';
}
/// Whether this is a congressional figure (has bioguide_id).
bool get isCongressional => bioguideId != null;
/// Parses a figure row from PostgREST JSON.
///
/// Throws [FormatException] if required fields are missing.
factory Figure.fromJson(Map<String, dynamic> json) {
final id = json['figure_id'];
if (id is! String || id.isEmpty) {
throw FormatException(
'Figure.fromJson: figure_id missing or invalid',
json,
);
}
final name = json['name'];
if (name is! String || name.isEmpty) {
throw FormatException(
'Figure.fromJson: name missing or invalid',
json,
);
}
final category = json['category'];
if (category is! String || category.isEmpty) {
throw FormatException(
'Figure.fromJson: category missing or invalid',
json,
);
}
final createdAtRaw = json['created_at'];
if (createdAtRaw is! String) {
throw FormatException(
'Figure.fromJson: created_at missing or invalid',
json,
);
}
final createdAt = DateTime.tryParse(createdAtRaw);
if (createdAt == null) {
throw FormatException(
'Figure.fromJson: created_at unparseable: $createdAtRaw',
);
}
// Parse metadata JSONB defensively - Supabase decoder may return
// Map<String, Object?> instead of Map<String, dynamic>.
final rawMetadata = json['metadata'];
final Map<String, dynamic> metadata = rawMetadata is Map
    ? Map<String, dynamic>.from(rawMetadata)
    : <String, dynamic>{};
// If the JSON has a top-level 'title' (flattened view) but metadata
// does not, inject it so the `role` getter picks it up.
final topTitle = json['title'];
if (topTitle is String && topTitle.isNotEmpty && metadata['title'] == null) {
  metadata['title'] = topTitle;
}
// Extract top-level photo_url column.
final rawPhotoUrl = json['photo_url'];
final photoUrl = rawPhotoUrl is String && rawPhotoUrl.isNotEmpty ? rawPhotoUrl : null;

return Figure(
figureId: id,
name: name,
category: category,
isActive: json['is_active'] as bool? ?? false,
activationOrder: (json['activation_order'] as num?)?.toInt(),
metadata: metadata.isEmpty ? null : metadata,
photoUrlDirect: photoUrl,
createdAt: createdAt.toUtc(),
);
}
/// Serializes for local caching / debugging.
Map<String, dynamic> toJson() => {
'figure_id': figureId,
'name': name,
'category': category,
'is_active': isActive,
'activation_order': activationOrder,
'metadata': metadata,
'photo_url': photoUrlDirect,
'created_at': createdAt.toIso8601String(),
};

  Map<String, double>? get framingDistribution => null;
  List<dynamic> get recentStatements => [];
  DateTime? get lastStatementAt => null;
  double? get avgSignalPulse => null;
  int get statementCount => recentStatements.length;
  String? get topTopic => null;
}
