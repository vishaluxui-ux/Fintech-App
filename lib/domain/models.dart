import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Lifecycle of an inbox item.
/// Only [approved] counts in totals (DSH-01, APR-02).
/// [rejected] is kept for parsing feedback and duplicate checks but never counts.
/// [deleted] is a soft delete so the deletion can sync; it never counts (APR-05).
enum ItemStatus { pending, approved, rejected, deleted }

enum CaptureSource { upiNotification, bill, manual, cash }

enum DuplicateMode { flag, autoReject }

/// Why a bill's lines did not match its printed total, as the user explained it.
enum MismatchReason { discount, printError, duplicateLine, other }

class Category {
  final String id;
  final String name;
  const Category(this.id, this.name);
}

/// CAT-01 default set. Changeable at approval time.
const defaultCategories = <Category>[
  Category('food', 'Food'),
  Category('groceries', 'Groceries'),
  Category('cosmetics', 'Cosmetics'),
  Category('shopping', 'Shopping'),
  Category('transport', 'Transport'),
  Category('bills', 'Bills & utilities'),
  Category('health', 'Health'),
  Category('entertainment', 'Entertainment'),
  Category('other', 'Other'),
];

Category categoryById(String id) =>
    defaultCategories.firstWhere((c) => c.id == id, orElse: () => defaultCategories.last);

/// A group of items: one bill, one payment, or one cash spend (APR-01).
class Capture {
  final String id;
  final CaptureSource source;
  final String? sourceApp; // e.g. "Google Pay"
  final DateTime capturedAt;
  final double? billTotal; // printed total on a bill (CAP-03)
  final String? imagePath; // local bill photo, kept or dropped per settings
  final String? withdrawalId; // cash spend allocated from an ATM withdrawal
  final MismatchReason? adjustReason; // set once a total mismatch is resolved
  final String? adjustNote; // "Other" reason text, or "auto" when the parser applied a discount
  const Capture({
    required this.id,
    required this.source,
    required this.capturedAt,
    this.sourceApp,
    this.billTotal,
    this.imagePath,
    this.withdrawalId,
    this.adjustReason,
    this.adjustNote,
  });

  Capture copyWith({
    String? imagePath,
    bool clearImage = false,
    double? billTotal,
    MismatchReason? adjustReason,
    String? adjustNote,
  }) =>
      Capture(
        id: id,
        source: source,
        sourceApp: sourceApp,
        capturedAt: capturedAt,
        billTotal: billTotal ?? this.billTotal,
        imagePath: clearImage ? null : (imagePath ?? this.imagePath),
        withdrawalId: withdrawalId,
        adjustReason: adjustReason ?? this.adjustReason,
        adjustNote: adjustNote ?? this.adjustNote,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'source': source.name,
        'source_app': sourceApp,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'bill_total': billTotal,
        'image_path': imagePath,
        'withdrawal_id': withdrawalId,
        'adjust_reason': adjustReason?.name,
        'adjust_note': adjustNote,
      };

  factory Capture.fromMap(Map<String, Object?> m) => Capture(
        id: m['id'] as String,
        source: CaptureSource.values.byName(m['source'] as String),
        sourceApp: m['source_app'] as String?,
        capturedAt: DateTime.parse(m['captured_at'] as String).toLocal(),
        billTotal: (m['bill_total'] as num?)?.toDouble(),
        imagePath: m['image_path'] as String?,
        withdrawalId: m['withdrawal_id'] as String?,
        adjustReason:
            m['adjust_reason'] == null ? null : MismatchReason.values.byName(m['adjust_reason'] as String),
        adjustNote: m['adjust_note'] as String?,
      );
}

class Item {
  final String id;
  final String captureId;
  final String name;
  final double amount;
  final String categoryId;
  final ItemStatus status;
  final DateTime spentAt;
  final String? flagReason; // APR-04 / duplicates
  final String? payee;
  final DateTime updatedAt;

  const Item({
    required this.id,
    required this.captureId,
    required this.name,
    required this.amount,
    required this.categoryId,
    required this.status,
    required this.spentAt,
    required this.updatedAt,
    this.flagReason,
    this.payee,
  });

  bool get counts => status == ItemStatus.approved;
  bool get isFlagged => flagReason != null;

  Item copyWith({
    String? name,
    double? amount,
    String? categoryId,
    ItemStatus? status,
    String? flagReason,
    bool clearFlag = false,
  }) =>
      Item(
        id: id,
        captureId: captureId,
        name: name ?? this.name,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        status: status ?? this.status,
        spentAt: spentAt,
        payee: payee,
        flagReason: clearFlag ? null : (flagReason ?? this.flagReason),
        updatedAt: DateTime.now(),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'capture_id': captureId,
        'name': name,
        'amount': amount,
        'category_id': categoryId,
        'status': status.name,
        'spent_at': spentAt.toUtc().toIso8601String(),
        'flag_reason': flagReason,
        'payee': payee,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Item.fromMap(Map<String, Object?> m) => Item(
        id: m['id'] as String,
        captureId: m['capture_id'] as String,
        name: m['name'] as String,
        amount: (m['amount'] as num).toDouble(),
        categoryId: m['category_id'] as String,
        status: ItemStatus.values.byName(m['status'] as String),
        spentAt: DateTime.parse(m['spent_at'] as String).toLocal(),
        flagReason: m['flag_reason'] as String?,
        payee: m['payee'] as String?,
        updatedAt: DateTime.parse(m['updated_at'] as String).toLocal(),
      );
}

/// An ATM withdrawal held as unallocated cash (CAP-05, CSH-01).
class Withdrawal {
  final String id;
  final double amount;
  final DateTime at;
  final String? sourceApp;
  const Withdrawal({required this.id, required this.amount, required this.at, this.sourceApp});

  Map<String, Object?> toMap() => {
        'id': id,
        'amount': amount,
        'at': at.toUtc().toIso8601String(),
        'source_app': sourceApp,
      };

  factory Withdrawal.fromMap(Map<String, Object?> m) => Withdrawal(
        id: m['id'] as String,
        amount: (m['amount'] as num).toDouble(),
        at: DateTime.parse(m['at'] as String).toLocal(),
        sourceApp: m['source_app'] as String?,
      );
}

/// One line extracted by the AI from a bill (CAP-02).
class ParsedLine {
  final String name;
  final double amount;
  final String categoryId;
  final double confidence;
  const ParsedLine(this.name, this.amount, this.categoryId, this.confidence);
}

class ParsedBill {
  final String? merchant;
  final double? total;
  final double? discount; // bill-wide discount printed on the bill
  final List<ParsedLine> lines;
  const ParsedBill({this.merchant, this.total, this.discount, required this.lines});
}
