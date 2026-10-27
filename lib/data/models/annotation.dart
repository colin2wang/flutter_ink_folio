/// 划线/笔记模型。
/// epub 用 CFI 定位；txt（回退引擎）用字符偏移定位，两者可并存。
class Annotation {
  Annotation({
    required this.id,
    required this.bookId,
    required this.kind, // 'highlight' | 'note'
    required this.text,
    required this.createdAt,
    this.note,
    this.cfiRange,
    this.startOffset,
    this.endOffset,
    this.chapterTitle,
    this.colorIndex = 2,
  });

  final String id;
  final String bookId;
  final String kind;
  final String text;
  final String? note;
  final String? cfiRange;
  final int? startOffset;
  final int? endOffset;
  final String? chapterTitle;
  final int colorIndex; // 灰阶高亮底色索引 1..5
  final int createdAt;

  Map<String, dynamic> toRow() => {
        'id': id,
        'bookId': bookId,
        'kind': kind,
        'text': text,
        'note': note,
        'cfiRange': cfiRange,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'chapterTitle': chapterTitle,
        'colorIndex': colorIndex,
        'createdAt': createdAt,
      };

  factory Annotation.fromRow(Map<String, dynamic> row) => Annotation(
        id: row['id'] as String,
        bookId: row['bookId'] as String,
        kind: (row['kind'] ?? 'highlight') as String,
        text: (row['text'] ?? '') as String,
        note: row['note'] as String?,
        cfiRange: row['cfiRange'] as String?,
        startOffset: row['startOffset'] as int?,
        endOffset: row['endOffset'] as int?,
        chapterTitle: row['chapterTitle'] as String?,
        colorIndex: (row['colorIndex'] ?? 2) as int,
        createdAt: (row['createdAt'] ?? 0) as int,
      );

  Map<String, dynamic> toJson() => toRow();
  factory Annotation.fromJson(Map<String, dynamic> j) => Annotation.fromRow(j);
}
