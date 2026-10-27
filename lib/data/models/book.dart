/// 书籍模型（书库 DB 行 + 阅读进度合一，避免多表 join 的过度设计）
class Book {
  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.kind,
    required this.addedAt,
    this.lastReadAt,
    this.percent = 0,
    this.cfi,
    this.startOffset = 0,
    this.chapterIndex = 0,
    this.colorIndex = 0,
  });

  final String id;
  final String title;
  final String author;
  final String filePath; // 沙盒绝对路径（web 下为空）
  final String kind; // 'txt' | 'epub'
  final int addedAt; // epoch ms
  int? lastReadAt; // epoch ms
  double percent; // 0..1
  String? cfi; // epub 进度（foliate CFI）
  int startOffset; // txt 进度（字符偏移）
  int chapterIndex;
  int colorIndex; // 书架占位封面灰阶索引（1..5）

  Map<String, dynamic> toRow() => {
        'id': id,
        'title': title,
        'author': author,
        'filePath': filePath,
        'kind': kind,
        'addedAt': addedAt,
        'lastReadAt': lastReadAt,
        'percent': percent,
        'cfi': cfi,
        'startOffset': startOffset,
        'chapterIndex': chapterIndex,
        'colorIndex': colorIndex,
      };

  factory Book.fromRow(Map<String, dynamic> row) => Book(
        id: row['id'] as String,
        title: (row['title'] ?? '') as String,
        author: (row['author'] ?? '') as String,
        filePath: (row['filePath'] ?? '') as String,
        kind: (row['kind'] ?? 'txt') as String,
        addedAt: (row['addedAt'] ?? 0) as int,
        lastReadAt: row['lastReadAt'] as int?,
        percent: ((row['percent'] ?? 0) as num).toDouble(),
        cfi: row['cfi'] as String?,
        startOffset: (row['startOffset'] ?? 0) as int,
        chapterIndex: (row['chapterIndex'] ?? 0) as int,
        colorIndex: (row['colorIndex'] ?? 0) as int,
      );

  Map<String, dynamic> toJson() => toRow();
  factory Book.fromJson(Map<String, dynamic> j) => Book.fromRow(j);
}
