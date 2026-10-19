import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────
// CONSTANTS & HELPERS
// ─────────────────────────────────────────────────────────────
const double kPageW = 800;
const double kPageH = 1131;
const double kBoardW = 6000;
const double kBoardH = 4000;
const Color kBrand = Color(0xFF4F46E5);
const Color kBrand2 = Color(0xFF9333EA);
const Color kBar = Color(0xFF2F5597);

const List<int> kFolderColors = [
  0xFFEC4899,
  0xFF4F46E5,
  0xFF10B981,
  0xFF8B5CF6,
  0xFFF59E0B,
  0xFF0EA5E9,
  0xFFEF4444,
  0xFF14B8A6,
];

const List<Color> kPenColors = [
  Colors.black,
  Color(0xFF6B7280),
  Color(0xFF1D4ED8),
  Color(0xFF0EA5E9),
  Color(0xFF16A34A),
  Color(0xFFF59E0B),
  Color(0xFFDC2626),
  Color(0xFFEC4899),
  Color(0xFF9333EA),
  Colors.white,
];

const List<Color> kHighlightColors = [
  Color(0xFFFFEB3B),
  Color(0xFF8BC34A),
  Color(0xFF4FC3F7),
  Color(0xFFFFAB91),
  Color(0xFFF48FB1),
  Color(0xFFCE93D8),
];

const List<Color> kStickyColors = [
  Color(0xFFFFF176),
  Color(0xFFF8BBD0),
  Color(0xFFC5E1A5),
  Color(0xFF81D4FA),
  Color(0xFFFFCC80),
];

const List<String> kStickers = [
  '😀', '😂', '😍', '🤔', '👍', '👏', '🔥', '⭐', '❤️', '✅', '❌', '❗',
  '❓', '💡', '📌', '📎', '📚', '✏️', '🎯', '🚀', '🧠', '⏰', '📅', '🎉',
];

int _idCounter = 0;
String newId() => '${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

double _r1(double v) => (v * 10).roundToDouble() / 10;

T? findFirst<T>(Iterable<T> items, bool Function(T) test) {
  for (final e in items) {
    if (test(e)) return e;
  }
  return null;
}

String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

Color _darken(Color c, [double amount = 0.14]) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness - amount).clamp(0.0, 1.0).toDouble())
      .toColor();
}

double _distToSeg(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 == 0) return (p - a).distance;
  final ap = p - a;
  final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / l2).clamp(0.0, 1.0).toDouble();
  return (p - (a + ab * t)).distance;
}

bool _pointInPolygon(Offset p, List<Offset> poly) {
  bool inside = false;
  for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i];
    final b = poly[j];
    if (((a.dy > p.dy) != (b.dy > p.dy)) &&
        (p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx)) {
      inside = !inside;
    }
  }
  return inside;
}

double measureTextHeight(String text, double fontSize, double width) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontSize: fontSize, height: 1.25)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(20.0, width));
  return tp.height;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final provider = NotesProvider();
  await provider.init();
  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      child: const NoteSmartApp(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// APP
// ─────────────────────────────────────────────────────────────
class NoteSmartApp extends StatelessWidget {
  const NoteSmartApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.watch<NotesProvider>().darkMode;
    return MaterialApp(
      title: 'NoteSmart',
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kBrand),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBrand,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LOGO + SPLASH
// ─────────────────────────────────────────────────────────────
class LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset o(double x, double y) => Offset(x * s, y * s);

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.22)),
      Paint()
        ..shader = const LinearGradient(
          colors: [kBrand, kBrand2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromPoints(o(0.25, 0.22), o(0.72, 0.82)), Radius.circular(s * 0.05)),
      Paint()..color = Colors.black.withOpacity(0.18),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromPoints(o(0.25, 0.20), o(0.72, 0.80)), Radius.circular(s * 0.05)),
      Paint()..color = Colors.white,
    );
    final line = Paint()..color = const Color(0xFFC7D2FE);
    for (final l in const [
      [0.34, 0.64],
      [0.44, 0.64],
      [0.54, 0.64],
      [0.64, 0.50],
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(o(0.33, l[0] - 0.012), o(l[1], l[0] + 0.012)),
          Radius.circular(s * 0.012),
        ),
        line,
      );
    }
    const tip = Offset(0.58, 0.80);
    const end = Offset(0.86, 0.38);
    final len = (end - tip).distance;
    final dir = (end - tip) / len;
    final nrm = Offset(-dir.dy, dir.dx);
    Offset pt(double t, double w) {
      final p = tip + dir * t + nrm * w;
      return o(p.dx, p.dy);
    }

    const hw = 0.04;
    void poly(List<Offset> pts, Color c) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = c);
    }

    poly([pt(0, 0), pt(0.12, hw), pt(0.12, -hw)], const Color(0xFFFDE0AB));
    poly([pt(0, 0), pt(0.045, hw * 0.35), pt(0.045, -hw * 0.35)],
        const Color(0xFF1E293B));
    poly([pt(0.12, hw), pt(0.44, hw), pt(0.44, -hw), pt(0.12, -hw)],
        const Color(0xFFFBBF24));
    poly([pt(0.44, hw), pt(0.50, hw), pt(0.50, -hw), pt(0.44, -hw)],
        const Color(0xFFF472B6));

    final c = o(0.79, 0.24);
    final star = Path();
    for (int i = 0; i < 8; i++) {
      final ang = math.pi / 4 * i - math.pi / 2;
      final rad = (i % 2 == 0 ? 0.095 : 0.026) * s;
      final p = Offset(c.dx + rad * math.cos(ang), c.dy + rad * math.sin(ang));
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: LogoPainter()));
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..forward();
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kBrand, kBrand2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _c, curve: Curves.easeIn),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.6, end: 1.0).animate(curved),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(40)),
                      boxShadow: [
                        BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 30,
                            offset: Offset(0, 12)),
                      ],
                    ),
                    child: AppLogo(size: 128),
                  ),
                  SizedBox(height: 24),
                  Text('NoteSmart',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text('Write. Draw. Think smarter.',
                      style: TextStyle(color: Colors.white70, fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────
class StrokePoint {
  final double x, y, pressure;
  const StrokePoint(this.x, this.y, [this.pressure = 1.0]);
}

class StrokeData {
  final List<StrokePoint> points;
  final int color;
  final double width;
  final String kind; // pen, ballpoint, pencil, brush, marker, highlighter
  Rect? _b;

  StrokeData({
    required this.points,
    required this.color,
    required this.width,
    this.kind = 'pen',
  });

  Rect get bounds {
    final cached = _b;
    if (cached != null) return cached;
    if (points.isEmpty) return Rect.zero;
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    final r = Rect.fromLTRB(
        minX - width / 2, minY - width / 2, maxX + width / 2, maxY + width / 2);
    _b = r;
    return r;
  }

  StrokeData translated(double dx, double dy) => StrokeData(
        points: points.map((p) => StrokePoint(p.x + dx, p.y + dy, p.pressure)).toList(),
        color: color,
        width: width,
        kind: kind,
      );

  Map<String, dynamic> toJson() {
    final flat = <double>[];
    for (final p in points) {
      flat
        ..add(_r1(p.x))
        ..add(_r1(p.y))
        ..add((p.pressure * 100).round() / 100);
    }
    return {'k': kind, 'c': color, 'w': width, 'p': flat};
  }

  factory StrokeData.fromJson(Map<String, dynamic> j) {
    final flat = (j['p'] as List).map((e) => (e as num).toDouble()).toList();
    final pts = <StrokePoint>[];
    for (int i = 0; i + 2 < flat.length; i += 3) {
      pts.add(StrokePoint(flat[i], flat[i + 1], flat[i + 2]));
    }
    return StrokeData(
      points: pts,
      color: j['c'] as int,
      width: (j['w'] as num).toDouble(),
      kind: j['k'] as String? ?? 'pen',
    );
  }
}

class PageObject {
  final String id;
  final String type; // image, text, sticky, sticker
  final double x, y, w, h, fontSize;
  final String path, text;
  final int color;

  const PageObject({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.path = '',
    this.text = '',
    this.color = 0xFF000000,
    this.fontSize = 24,
  });

  Rect get rect => Rect.fromLTWH(x, y, w, h);

  PageObject copyWith({
    double? x,
    double? y,
    double? w,
    double? h,
    String? text,
    String? id,
  }) =>
      PageObject(
        id: id ?? this.id,
        type: type,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        path: path,
        text: text ?? this.text,
        color: color,
        fontSize: fontSize,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'path': path,
        'text': text,
        'color': color,
        'fs': fontSize,
      };

  factory PageObject.fromJson(Map<String, dynamic> j) => PageObject(
        id: j['id'] as String,
        type: j['type'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        w: (j['w'] as num).toDouble(),
        h: (j['h'] as num).toDouble(),
        path: j['path'] as String? ?? '',
        text: j['text'] as String? ?? '',
        color: j['color'] as int? ?? 0xFF000000,
        fontSize: (j['fs'] as num?)?.toDouble() ?? 24,
      );
}

class NotePage {
  String id;
  String title;
  String background; // blank, lined, grid, dotted, cornell, music
  int paper;
  double w, h;
  String? bgImage;
  String textContent;
  List<StrokeData> strokes;
  List<PageObject> objects;
  DateTime createdAt;
  DateTime updatedAt;

  NotePage({
    String? id,
    this.title = 'Untitled',
    this.background = 'lined',
    this.paper = 0xFFFFFFFF,
    this.w = kPageW,
    this.h = kPageH,
    this.bgImage,
    this.textContent = '',
    List<StrokeData>? strokes,
    List<PageObject>? objects,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? newId(),
        strokes = strokes ?? [],
        objects = objects ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isBoard => w > 2000;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'bg': background,
        'paper': paper,
        'w': w,
        'h': h,
        'bgImage': bgImage,
        'text': textContent,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'objects': objects.map((o) => o.toJson()).toList(),
        'created': createdAt.toIso8601String(),
        'updated': updatedAt.toIso8601String(),
      };

  factory NotePage.fromJson(Map<String, dynamic> j) => NotePage(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Untitled',
        background: j['bg'] as String? ?? 'blank',
        paper: j['paper'] as int? ?? 0xFFFFFFFF,
        w: (j['w'] as num?)?.toDouble() ?? kPageW,
        h: (j['h'] as num?)?.toDouble() ?? kPageH,
        bgImage: j['bgImage'] as String?,
        textContent: j['text'] as String? ?? '',
        strokes: (j['strokes'] as List?)
                ?.map((e) => StrokeData.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        objects: (j['objects'] as List?)
                ?.map((e) => PageObject.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: DateTime.tryParse(j['created'] as String? ?? ''),
        updatedAt: DateTime.tryParse(j['updated'] as String? ?? ''),
      );
}

class Notebook {
  String id;
  String name;
  String kind; // notebook, board, pdf
  int color;
  String? folderId;
  List<NotePage> pages;
  DateTime createdAt;
  DateTime updatedAt;

  Notebook({
    String? id,
    this.name = 'Notebook',
    this.kind = 'notebook',
    this.color = 0xFF4F46E5,
    this.folderId,
    List<NotePage>? pages,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? newId(),
        pages = pages ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'color': color,
        'folder': folderId,
        'pages': pages.map((p) => p.toJson()).toList(),
        'created': createdAt.toIso8601String(),
        'updated': updatedAt.toIso8601String(),
      };

  factory Notebook.fromJson(Map<String, dynamic> j) => Notebook(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Notebook',
        kind: j['kind'] as String? ?? 'notebook',
        color: j['color'] as int? ?? 0xFF4F46E5,
        folderId: j['folder'] as String?,
        pages: (j['pages'] as List?)
                ?.map((e) => NotePage.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: DateTime.tryParse(j['created'] as String? ?? ''),
        updatedAt: DateTime.tryParse(j['updated'] as String? ?? ''),
      );
}

class Folder {
  String id;
  String name;
  int color;
  Folder({String? id, required this.name, this.color = 0xFF4F46E5})
      : id = id ?? newId();

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};
  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Folder',
        color: j['color'] as int? ?? 0xFF4F46E5,
      );
}

enum ToolType { select, pen, highlighter, eraser, text, shape, sticky, laser }

IconData kindIcon(String kind) {
  switch (kind) {
    case 'board':
      return Icons.dashboard_outlined;
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    default:
      return Icons.menu_book;
  }
}

String kindLabel(String kind) {
  switch (kind) {
    case 'board':
      return 'Whiteboard';
    case 'pdf':
      return 'PDF';
    default:
      return 'Notebook';
  }
}

// ─────────────────────────────────────────────────────────────
// PROVIDER (library, settings, storage)
// ─────────────────────────────────────────────────────────────
class NotesProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const _settingsKey = 'settings_v2';

  List<Notebook> notebooks = [];
  List<Folder> folders = [];
  String? folderFilter; // null = all notes
  String? currentNotebookId;
  String? currentPageId;

  String apiKey = '';
  String baseUrl = 'https://api.openai.com/v1';
  String model = 'gpt-4o-mini';
  bool darkMode = false;

  ToolType tool = ToolType.pen;
  String penKind = 'pen';
  Color penColor = Colors.black;
  double penWidth = 4;
  Color highlightColor = const Color(0xFFFFEB3B);
  double highlightWidth = 24;
  String shapeType = 'rect';
  bool autoShape = false;
  double textSize = 28;
  Color stickyColor = const Color(0xFFFFF176);

  late Directory dir;
  late Directory mediaDir;
  final Set<String> _dirty = {};
  bool _libDirty = false;
  Timer? _timer;

  String _path(String name) => '${dir.path}${Platform.pathSeparator}$name';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_settingsKey);
    if (s != null) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        apiKey = m['apiKey'] as String? ?? '';
        baseUrl = m['baseUrl'] as String? ?? baseUrl;
        model = m['model'] as String? ?? model;
        darkMode = m['darkMode'] as bool? ?? false;
      } catch (_) {}
    }

    final base = await getApplicationDocumentsDirectory();
    dir = Directory('${base.path}${Platform.pathSeparator}notesmart');
    await dir.create(recursive: true);
    mediaDir = Directory('${dir.path}${Platform.pathSeparator}media');
    await mediaDir.create(recursive: true);

    final lib = File(_path('library.json'));
    if (await lib.exists()) {
      try {
        final j = jsonDecode(await lib.readAsString()) as Map<String, dynamic>;
        folders = (j['folders'] as List? ?? [])
            .map((e) => Folder.fromJson(e as Map<String, dynamic>))
            .toList();
        for (final id in (j['order'] as List? ?? [])) {
          final f = File(_path('nb_$id.json'));
          if (await f.exists()) {
            try {
              notebooks.add(Notebook.fromJson(
                  jsonDecode(await f.readAsString()) as Map<String, dynamic>));
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    for (final nb in notebooks) {
      if (nb.pages.isEmpty) nb.pages.add(NotePage());
    }
    if (notebooks.isEmpty) {
      final nb = Notebook(name: 'Welcome', color: 0xFF4F46E5);
      final pg = NotePage(title: 'Welcome');
      pg.objects.add(PageObject(
        id: newId(),
        type: 'text',
        x: 110,
        y: 70,
        w: 600,
        h: 200,
        text:
            'Welcome to NoteSmart\n\nWrite with the pen. Hold still at the end of a stroke to snap it into a perfect shape.',
        color: 0xFF1D4ED8,
        fontSize: 28,
      ));
      pg.objects.add(PageObject(
        id: newId(),
        type: 'sticky',
        x: 130,
        y: 360,
        w: 300,
        h: 230,
        text:
            'Try: shapes, photos, sticky notes, lasso select, PDF import and whiteboards.',
        color: 0xFFFFF176,
        fontSize: 22,
      ));
      nb.pages.add(pg);
      notebooks.add(nb);
      _dirty.add(nb.id);
      _libDirty = true;
      await flush();
    }
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) flush();
  }

  // ── persistence ──
  void persist() {
    final nb = currentNotebook;
    if (nb != null) {
      nb.updatedAt = DateTime.now();
      _dirty.add(nb.id);
    }
    _schedule();
  }

  void persistLibrary() {
    _libDirty = true;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    final ids = _dirty.toList();
    _dirty.clear();
    for (final id in ids) {
      final nb = findFirst(notebooks, (n) => n.id == id);
      if (nb == null) continue;
      try {
        await File(_path('nb_$id.json')).writeAsString(jsonEncode(nb.toJson()));
      } catch (_) {}
    }
    if (_libDirty) {
      _libDirty = false;
      try {
        await File(_path('library.json')).writeAsString(jsonEncode({
          'folders': folders.map((f) => f.toJson()).toList(),
          'order': notebooks.map((n) => n.id).toList(),
        }));
      } catch (_) {}
    }
  }

  Future<void> persistSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _settingsKey,
      jsonEncode({
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'model': model,
        'darkMode': darkMode,
      }),
    );
  }

  void refresh() => notifyListeners();

  // ── getters ──
  Notebook? get currentNotebook =>
      findFirst(notebooks, (n) => n.id == currentNotebookId);

  NotePage? get currentPage {
    final nb = currentNotebook;
    if (nb == null) return null;
    return findFirst(nb.pages, (p) => p.id == currentPageId);
  }

  List<Notebook> visibleNotebooks(String query) {
    final q = query.trim().toLowerCase();
    final list = notebooks.where((nb) {
      if (folderFilter != null && nb.folderId != folderFilter) return false;
      if (q.isEmpty) return true;
      if (nb.name.toLowerCase().contains(q)) return true;
      for (final p in nb.pages) {
        if (p.title.toLowerCase().contains(q) ||
            p.textContent.toLowerCase().contains(q)) {
          return true;
        }
        for (final o in p.objects) {
          if (o.text.toLowerCase().contains(q)) return true;
        }
      }
      return false;
    }).toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  // ── library actions ──
  void update(VoidCallback f) {
    f();
    notifyListeners();
  }

  void setFolder(String? id) {
    folderFilter = id;
    notifyListeners();
  }

  Notebook createNotebook({
    required String name,
    required String kind,
    String template = 'lined',
  }) {
    final nb = Notebook(
      name: name,
      kind: kind,
      color: kFolderColors[notebooks.length % kFolderColors.length],
      folderId: folderFilter,
    );
    if (kind == 'board') {
      nb.pages.add(NotePage(
          title: 'Board', background: 'dotted', w: kBoardW, h: kBoardH));
    } else {
      nb.pages.add(NotePage(title: 'Page 1', background: template));
    }
    notebooks.insert(0, nb);
    _dirty.add(nb.id);
    persistLibrary();
    notifyListeners();
    return nb;
  }

  Future<Notebook> importPdf(
      String srcPath, String name, void Function(int) onProgress) async {
    final bytes = await File(srcPath).readAsBytes();
    final nb = Notebook(
      name: name,
      kind: 'pdf',
      color: kFolderColors[notebooks.length % kFolderColors.length],
      folderId: folderFilter,
    );
    int i = 0;
    await for (final r in Printing.raster(bytes, dpi: 110)) {
      final png = await r.toPng();
      final f = File('${mediaDir.path}${Platform.pathSeparator}pdf_${nb.id}_$i.png');
      await f.writeAsBytes(png);
      nb.pages.add(NotePage(
        title: 'Page ${i + 1}',
        background: 'blank',
        bgImage: f.path,
        h: kPageW * r.height / r.width,
      ));
      i++;
      onProgress(i);
    }
    if (nb.pages.isEmpty) throw Exception('No pages found in this PDF.');
    notebooks.insert(0, nb);
    _dirty.add(nb.id);
    persistLibrary();
    notifyListeners();
    return nb;
  }

  void openNotebook(Notebook nb, {String? pageId}) {
    currentNotebookId = nb.id;
    currentPageId = pageId ?? nb.pages.first.id;
    notifyListeners();
  }

  void deleteNotebook(String id) {
    final nb = findFirst(notebooks, (n) => n.id == id);
    if (nb != null) {
      for (final pg in nb.pages) {
        _delFile(pg.bgImage);
        for (final o in pg.objects) {
          if (o.type == 'image') _delFile(o.path);
        }
      }
    }
    notebooks.removeWhere((n) => n.id == id);
    _delFile(_path('nb_$id.json'));
    _dirty.remove(id);
    persistLibrary();
    notifyListeners();
  }

  void _delFile(String? path) {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void renameNotebook(String id, String name) {
    final nb = findFirst(notebooks, (n) => n.id == id);
    if (nb == null) return;
    nb.name = name;
    _dirty.add(id);
    _schedule();
    notifyListeners();
  }

  void moveNotebook(String id, String? folderId) {
    final nb = findFirst(notebooks, (n) => n.id == id);
    if (nb == null) return;
    nb.folderId = folderId;
    _dirty.add(id);
    _schedule();
    notifyListeners();
  }

  void addFolder(String name) {
    folders.add(Folder(
        name: name, color: kFolderColors[folders.length % kFolderColors.length]));
    persistLibrary();
    notifyListeners();
  }

  void renameFolder(String id, String name) {
    final f = findFirst(folders, (x) => x.id == id);
    if (f == null) return;
    f.name = name;
    persistLibrary();
    notifyListeners();
  }

  void recolorFolder(String id, int color) {
    final f = findFirst(folders, (x) => x.id == id);
    if (f == null) return;
    f.color = color;
    persistLibrary();
    notifyListeners();
  }

  void deleteFolder(String id) {
    folders.removeWhere((f) => f.id == id);
    for (final nb in notebooks) {
      if (nb.folderId == id) {
        nb.folderId = null;
        _dirty.add(nb.id);
      }
    }
    if (folderFilter == id) folderFilter = null;
    persistLibrary();
    notifyListeners();
  }

  // ── page actions ──
  void selectPage(String id) {
    currentPageId = id;
    notifyListeners();
  }

  void addPage() {
    final nb = currentNotebook;
    if (nb == null) return;
    final cur = currentPage;
    final idx = cur == null ? nb.pages.length - 1 : nb.pages.indexOf(cur);
    final bg = (cur == null || cur.bgImage != null) ? 'lined' : cur.background;
    final paper = cur?.paper ?? 0xFFFFFFFF;
    final pg = nb.kind == 'board'
        ? NotePage(
            title: 'Board ${nb.pages.length + 1}',
            background: 'dotted',
            w: kBoardW,
            h: kBoardH,
            paper: paper)
        : NotePage(
            title: 'Page ${nb.pages.length + 1}', background: bg, paper: paper);
    nb.pages.insert(idx + 1, pg);
    currentPageId = pg.id;
    persist();
    notifyListeners();
  }

  void duplicatePage(String id) {
    final nb = currentNotebook;
    if (nb == null) return;
    final pg = findFirst(nb.pages, (p) => p.id == id);
    if (pg == null) return;
    final copy = NotePage.fromJson(
        jsonDecode(jsonEncode(pg.toJson())) as Map<String, dynamic>);
    copy.id = newId();
    copy.title = '${pg.title} copy';
    nb.pages.insert(nb.pages.indexOf(pg) + 1, copy);
    currentPageId = copy.id;
    persist();
    notifyListeners();
  }

  void movePage(String id, int delta) {
    final nb = currentNotebook;
    if (nb == null) return;
    final i = nb.pages.indexWhere((p) => p.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= nb.pages.length) return;
    final pg = nb.pages.removeAt(i);
    nb.pages.insert(j, pg);
    persist();
    notifyListeners();
  }

  void deletePage(String id) {
    final nb = currentNotebook;
    if (nb == null || nb.pages.length <= 1) return;
    nb.pages.removeWhere((p) => p.id == id);
    if (currentPageId == id) currentPageId = nb.pages.first.id;
    persist();
    notifyListeners();
  }

  void renamePage(String id, String title) {
    final nb = currentNotebook;
    if (nb == null) return;
    final p = findFirst(nb.pages, (x) => x.id == id);
    if (p == null) return;
    p.title = title;
    persist();
    notifyListeners();
  }

  void setBackground(String bg) {
    final p = currentPage;
    if (p == null) return;
    p.background = bg;
    persist();
    notifyListeners();
  }

  void setPaper(int color) {
    final p = currentPage;
    if (p == null) return;
    p.paper = color;
    persist();
    notifyListeners();
  }

  void setPageText(String text) {
    final p = currentPage;
    if (p == null) return;
    p.textContent = text;
    persist();
  }

  // ── settings ──
  void setDarkMode(bool v) {
    darkMode = v;
    persistSettings();
    notifyListeners();
  }

  void saveApiSettings(
      {required String key, required String url, required String modelName}) {
    apiKey = key;
    baseUrl = url;
    model = modelName;
    persistSettings();
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────
// SHAPES (recognition + generation)
// ─────────────────────────────────────────────────────────────
List<Offset> _densify(List<Offset> pts, {double step = 5}) {
  final out = <Offset>[];
  for (int i = 0; i < pts.length - 1; i++) {
    final a = pts[i];
    final b = pts[i + 1];
    final n = math.max(1, ((b - a).distance / step).ceil());
    for (int k = 0; k < n; k++) {
      out.add(Offset.lerp(a, b, k / n)!);
    }
  }
  out.add(pts.last);
  return out;
}

List<StrokePoint> _toPts(List<Offset> o) =>
    o.map((e) => StrokePoint(e.dx, e.dy, 1.0)).toList();

List<Offset> _rdp(List<Offset> pts, double eps) {
  if (pts.length < 3) return pts;
  double maxD = 0;
  int idx = 0;
  final a = pts.first;
  final b = pts.last;
  for (int i = 1; i < pts.length - 1; i++) {
    final d = _distToSeg(pts[i], a, b);
    if (d > maxD) {
      maxD = d;
      idx = i;
    }
  }
  if (maxD > eps) {
    final l = _rdp(pts.sublist(0, idx + 1), eps);
    final r = _rdp(pts.sublist(idx), eps);
    return [...l.sublist(0, l.length - 1), ...r];
  }
  return [a, b];
}

List<StrokePoint> shapePoints(String type, Offset a, Offset b) {
  final r = Rect.fromPoints(a, b);
  switch (type) {
    case 'line':
      return _toPts(_densify([a, b]));
    case 'arrow':
      {
        final d = b - a;
        final len = d.distance;
        if (len < 2) return _toPts([a, b]);
        final u = d / len;
        final hl = math.min(30.0, len * 0.35);
        Offset rot(Offset v, double ang) => Offset(
            v.dx * math.cos(ang) - v.dy * math.sin(ang),
            v.dx * math.sin(ang) + v.dy * math.cos(ang));
        final h1 = b - rot(u, 0.5) * hl;
        final h2 = b - rot(u, -0.5) * hl;
        return _toPts(_densify([a, b, h1, b, h2]));
      }
    case 'ellipse':
      {
        final pts = <Offset>[];
        for (int i = 0; i <= 72; i++) {
          final ang = 2 * math.pi * i / 72;
          pts.add(Offset(r.center.dx + r.width / 2 * math.cos(ang),
              r.center.dy + r.height / 2 * math.sin(ang)));
        }
        return _toPts(pts);
      }
    case 'triangle':
      return _toPts(_densify([
        Offset(r.center.dx, r.top),
        r.bottomRight,
        r.bottomLeft,
        Offset(r.center.dx, r.top),
      ]));
    case 'diamond':
      return _toPts(_densify([
        Offset(r.center.dx, r.top),
        Offset(r.right, r.center.dy),
        Offset(r.center.dx, r.bottom),
        Offset(r.left, r.center.dy),
        Offset(r.center.dx, r.top),
      ]));
    default:
      return _toPts(_densify([
        r.topLeft,
        r.topRight,
        r.bottomRight,
        r.bottomLeft,
        r.topLeft,
      ]));
  }
}

/// Turns a rough hand-drawn stroke into a perfect line / ellipse / triangle /
/// rectangle. Returns null when nothing is recognised.
List<StrokePoint>? recognizeShape(List<StrokePoint> sp) {
  if (sp.length < 6) return null;
  final pts = sp.map((p) => Offset(p.x, p.y)).toList();
  double pathLen = 0;
  for (int i = 1; i < pts.length; i++) {
    pathLen += (pts[i] - pts[i - 1]).distance;
  }
  if (pathLen < 60) return null;
  final first = pts.first;
  final last = pts.last;
  final chord = (last - first).distance;

  double minX = double.infinity, minY = double.infinity;
  double maxX = -double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, p.dx);
    minY = math.min(minY, p.dy);
    maxX = math.max(maxX, p.dx);
    maxY = math.max(maxY, p.dy);
  }
  final bw = maxX - minX;
  final bh = maxY - minY;
  final diag = math.sqrt(bw * bw + bh * bh);

  // straight line
  if (chord > 50 && chord / pathLen > 0.9) {
    double maxDev = 0;
    for (final p in pts) {
      maxDev = math.max(maxDev, _distToSeg(p, first, last));
    }
    if (maxDev < 0.07 * chord + 2) {
      return _toPts(_densify([first, last]));
    }
  }

  // closed shapes
  if (chord < 0.3 * pathLen && pathLen > 120 && bw > 20 && bh > 20) {
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final rx = bw / 2;
    final ry = bh / 2;
    double dev = 0;
    for (final p in pts) {
      final nx = (p.dx - cx) / rx;
      final ny = (p.dy - cy) / ry;
      dev += (math.sqrt(nx * nx + ny * ny) - 1).abs();
    }
    dev /= pts.length;
    if (dev < 0.14) {
      final circle = (rx - ry).abs() / math.max(rx, ry) < 0.15;
      final ax = circle ? (rx + ry) / 2 : rx;
      final ay = circle ? (rx + ry) / 2 : ry;
      final out = <Offset>[];
      for (int i = 0; i <= 72; i++) {
        final ang = 2 * math.pi * i / 72;
        out.add(Offset(cx + ax * math.cos(ang), cy + ay * math.sin(ang)));
      }
      return _toPts(out);
    }

    final closed = [...pts, pts.first];
    var v = _rdp(closed, math.max(10.0, diag * 0.06));
    if (v.length > 1 && (v.first - v.last).distance < 1) v = v.sublist(0, v.length - 1);
    if (v.length == 3) {
      return _toPts(_densify([v[0], v[1], v[2], v[0]]));
    }
    if (v.length == 4) {
      bool rectLike = true;
      bool axisAligned = true;
      for (int i = 0; i < 4; i++) {
        final p0 = v[(i + 3) % 4];
        final p1 = v[i];
        final p2 = v[(i + 1) % 4];
        final e1 = p0 - p1;
        final e2 = p2 - p1;
        final cosA = (e1.dx * e2.dx + e1.dy * e2.dy) /
            (e1.distance * e2.distance + 1e-9);
        final ang = math.acos(cosA.clamp(-1.0, 1.0).toDouble()) * 180 / math.pi;
        if ((ang - 90).abs() > 22) rectLike = false;
        final edgeAng = (math.atan2(e2.dy, e2.dx) * 180 / math.pi).abs() % 90;
        if (edgeAng > 14 && edgeAng < 76) axisAligned = false;
      }
      if (rectLike && axisAligned) {
        final r = Rect.fromLTRB(minX, minY, maxX, maxY);
        return _toPts(_densify(
            [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft, r.topLeft]));
      }
      return _toPts(_densify([v[0], v[1], v[2], v[3], v[0]]));
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────
// DRAWING CONTROLLER
// ─────────────────────────────────────────────────────────────
class _Snap {
  final List<StrokeData> strokes;
  final List<PageObject> objects;
  _Snap(this.strokes, this.objects);
}

class LaserPoint {
  final Offset pos;
  final int ms;
  LaserPoint(this.pos, this.ms);
}

bool _strokeHit(StrokeData s, Offset q, double r) {
  if (!s.bounds.inflate(r).contains(q)) return false;
  final pts = s.points;
  final tol = r + s.width / 2;
  if (pts.length == 1) return (Offset(pts[0].x, pts[0].y) - q).distance <= tol;
  for (int i = 0; i < pts.length - 1; i++) {
    if (_distToSeg(q, Offset(pts[i].x, pts[i].y),
            Offset(pts[i + 1].x, pts[i + 1].y)) <=
        tol) {
      return true;
    }
  }
  return false;
}

class DrawingController extends ChangeNotifier {
  List<StrokeData> strokes = [];
  List<PageObject> objects = [];
  StrokeData? active;
  StrokeData? preview;
  Set<StrokeData> selStrokes = {};
  Set<String> selObjIds = {};
  List<Offset> lasso = [];
  List<LaserPoint> laser = [];
  int strokeVer = 0;
  final List<_Snap> _undo = [];
  final List<_Snap> _redo = [];
  bool _erasePushed = false;
  bool _movePushed = false;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get hasSelection => selStrokes.isNotEmpty || selObjIds.isNotEmpty;

  void touch() => notifyListeners();

  PageObject? get singleObject {
    if (selStrokes.isEmpty && selObjIds.length == 1) {
      return findFirst(objects, (o) => o.id == selObjIds.first);
    }
    return null;
  }

  /// Called from build(): must not notify.
  void loadFrom(NotePage pg) {
    strokes = List.from(pg.strokes);
    objects = List.from(pg.objects);
    _undo.clear();
    _redo.clear();
    active = null;
    preview = null;
    selStrokes = {};
    selObjIds = {};
    lasso = [];
    laser = [];
    strokeVer++;
  }

  void _pushUndo() {
    _undo.add(_Snap(List.from(strokes), List.from(objects)));
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
  }

  // strokes
  void beginStroke(StrokeData s) {
    _pushUndo();
    active = s;
    notifyListeners();
  }

  void extendStroke(StrokePoint p) {
    active?.points.add(p);
    notifyListeners();
  }

  void replaceActive(List<StrokePoint> pts) {
    final a = active;
    if (a == null) return;
    active = StrokeData(points: pts, color: a.color, width: a.width, kind: a.kind);
    notifyListeners();
  }

  void endStroke() {
    final a = active;
    if (a == null) return;
    strokes.add(a);
    active = null;
    strokeVer++;
    notifyListeners();
  }

  void cancelStroke() {
    if (active == null) return;
    active = null;
    if (_undo.isNotEmpty) _undo.removeLast();
    notifyListeners();
  }

  void addStroke(StrokeData s) {
    _pushUndo();
    strokes.add(s);
    strokeVer++;
    notifyListeners();
  }

  void setPreview(StrokeData? s) {
    preview = s;
    notifyListeners();
  }

  void beginErase() => _erasePushed = false;

  void eraseAlong(Offset a, Offset b, double r) {
    final steps = math.max(1, ((b - a).distance / (r * 0.6)).ceil());
    final hit = <StrokeData>{};
    for (int i = 0; i <= steps; i++) {
      final q = Offset.lerp(a, b, i / steps)!;
      for (final s in strokes) {
        if (!hit.contains(s) && _strokeHit(s, q, r)) hit.add(s);
      }
    }
    if (hit.isEmpty) return;
    if (!_erasePushed) {
      _pushUndo();
      _erasePushed = true;
    }
    strokes = strokes.where((s) => !hit.contains(s)).toList();
    strokeVer++;
    notifyListeners();
  }

  void clearInk() {
    if (strokes.isEmpty) return;
    _pushUndo();
    strokes = [];
    selStrokes = {};
    strokeVer++;
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_Snap(List.from(strokes), List.from(objects)));
    final s = _undo.removeLast();
    strokes = s.strokes;
    objects = s.objects;
    selStrokes = {};
    selObjIds = {};
    strokeVer++;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_Snap(List.from(strokes), List.from(objects)));
    final s = _redo.removeLast();
    strokes = s.strokes;
    objects = s.objects;
    selStrokes = {};
    selObjIds = {};
    strokeVer++;
    notifyListeners();
  }

  // objects
  void addObject(PageObject o) {
    _pushUndo();
    objects.add(o);
    notifyListeners();
  }

  void updateObject(PageObject o) {
    _pushUndo();
    objects = [for (final x in objects) x.id == o.id ? o : x];
    notifyListeners();
  }

  PageObject? objectAt(Offset q) {
    for (int i = objects.length - 1; i >= 0; i--) {
      if (objects[i].rect.inflate(4).contains(q)) return objects[i];
    }
    return null;
  }

  StrokeData? strokeAt(Offset q, double tol) {
    for (int i = strokes.length - 1; i >= 0; i--) {
      if (_strokeHit(strokes[i], q, tol)) return strokes[i];
    }
    return null;
  }

  // selection
  void selectOnly({PageObject? object, StrokeData? stroke}) {
    selStrokes = {};
    selObjIds = {};
    if (object != null) selObjIds.add(object.id);
    if (stroke != null) selStrokes.add(stroke);
    notifyListeners();
  }

  void clearSelection() {
    if (!hasSelection && lasso.isEmpty) return;
    selStrokes = {};
    selObjIds = {};
    lasso = [];
    notifyListeners();
  }

  Rect? selectionRect() {
    Rect? r;
    for (final s in selStrokes) {
      r = r == null ? s.bounds : r.expandToInclude(s.bounds);
    }
    for (final o in objects) {
      if (selObjIds.contains(o.id)) {
        r = r == null ? o.rect : r.expandToInclude(o.rect);
      }
    }
    return r?.inflate(6);
  }

  void beginMove() => _movePushed = false;

  void _pushMoveOnce() {
    if (!_movePushed) {
      _pushUndo();
      _movePushed = true;
    }
  }

  void moveSelection(Offset d) {
    _pushMoveOnce();
    if (selStrokes.isNotEmpty) {
      final ns = <StrokeData>{};
      final list = <StrokeData>[];
      for (final s in strokes) {
        if (selStrokes.contains(s)) {
          final t = s.translated(d.dx, d.dy);
          ns.add(t);
          list.add(t);
        } else {
          list.add(s);
        }
      }
      strokes = list;
      selStrokes = ns;
      strokeVer++;
    }
    if (selObjIds.isNotEmpty) {
      objects = [
        for (final o in objects)
          selObjIds.contains(o.id) ? o.copyWith(x: o.x + d.dx, y: o.y + d.dy) : o
      ];
    }
    notifyListeners();
  }

  void resizeSingle(Offset q) {
    final o = singleObject;
    if (o == null) return;
    _pushMoveOnce();
    PageObject n;
    if (o.type == 'image' || o.type == 'sticker') {
      final nw = math.max(40.0, q.dx - o.x);
      n = o.copyWith(w: nw, h: o.h * (nw / o.w));
    } else {
      n = o.copyWith(w: math.max(80.0, q.dx - o.x), h: math.max(50.0, q.dy - o.y));
    }
    objects = [for (final x in objects) x.id == o.id ? n : x];
    notifyListeners();
  }

  void deleteSelection() {
    if (!hasSelection) return;
    _pushUndo();
    strokes = strokes.where((s) => !selStrokes.contains(s)).toList();
    objects = objects.where((o) => !selObjIds.contains(o.id)).toList();
    selStrokes = {};
    selObjIds = {};
    strokeVer++;
    notifyListeners();
  }

  void duplicateSelection() {
    if (!hasSelection) return;
    _pushUndo();
    const off = 36.0;
    final newS = <StrokeData>{};
    for (final s in selStrokes) {
      final t = s.translated(off, off);
      strokes.add(t);
      newS.add(t);
    }
    final newIds = <String>{};
    for (final o in List<PageObject>.from(objects)) {
      if (selObjIds.contains(o.id)) {
        final c = o.copyWith(id: newId(), x: o.x + off, y: o.y + off);
        objects.add(c);
        newIds.add(c.id);
      }
    }
    selStrokes = newS;
    selObjIds = newIds;
    strokeVer++;
    notifyListeners();
  }

  void finishLasso() {
    final poly = lasso;
    lasso = [];
    selStrokes = {};
    selObjIds = {};
    if (poly.length >= 6) {
      Rect pb = Rect.fromPoints(poly.first, poly.first);
      for (final p in poly) {
        pb = pb.expandToInclude(Rect.fromPoints(p, p));
      }
      if (pb.width > 8 || pb.height > 8) {
        for (final s in strokes) {
          if (!s.bounds.overlaps(pb)) continue;
          int inside = 0;
          for (final p in s.points) {
            if (_pointInPolygon(Offset(p.x, p.y), poly)) inside++;
          }
          if (inside >= s.points.length * 0.6) selStrokes.add(s);
        }
        for (final o in objects) {
          if (_pointInPolygon(o.rect.center, poly)) selObjIds.add(o.id);
        }
      }
    }
    notifyListeners();
  }

  // laser
  void addLaser(Offset p) {
    laser.add(LaserPoint(p, DateTime.now().millisecondsSinceEpoch));
    if (laser.length > 50) laser.removeAt(0);
    notifyListeners();
  }

  void pruneLaser() {
    final now = DateTime.now().millisecondsSinceEpoch;
    laser.removeWhere((l) => now - l.ms > 700);
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────
// PAINTING
// ─────────────────────────────────────────────────────────────
void drawStroke(Canvas canvas, StrokeData s) {
  final pts = s.points;
  if (pts.isEmpty) return;
  final base = Color(s.color);
  final kind = s.kind;

  if (pts.length == 1) {
    canvas.drawCircle(
      Offset(pts[0].x, pts[0].y),
      s.width / 2,
      Paint()..color = kind == 'highlighter' ? base.withOpacity(0.35) : base,
    );
    return;
  }

  if (kind == 'pen' || kind == 'brush') {
    final paint = Paint()
      ..color = base
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    double widthFor(double pr) =>
        kind == 'pen' ? s.width * (0.4 + 0.6 * pr) : s.width * (0.25 + 1.0 * pr);
    Offset prev = Offset(pts[0].x, pts[0].y);
    for (int i = 1; i < pts.length - 1; i++) {
      final m = Offset((pts[i].x + pts[i + 1].x) / 2, (pts[i].y + pts[i + 1].y) / 2);
      paint.strokeWidth = widthFor((pts[i].pressure + pts[i - 1].pressure) / 2);
      final path = Path()
        ..moveTo(prev.dx, prev.dy)
        ..quadraticBezierTo(pts[i].x, pts[i].y, m.dx, m.dy);
      canvas.drawPath(path, paint);
      prev = m;
    }
    paint.strokeWidth = widthFor(pts.last.pressure);
    canvas.drawLine(prev, Offset(pts.last.x, pts.last.y), paint);
    return;
  }

  final path = Path()..moveTo(pts[0].x, pts[0].y);
  for (int i = 1; i < pts.length - 1; i++) {
    final m = Offset((pts[i].x + pts[i + 1].x) / 2, (pts[i].y + pts[i + 1].y) / 2);
    path.quadraticBezierTo(pts[i].x, pts[i].y, m.dx, m.dy);
  }
  path.lineTo(pts.last.x, pts.last.y);
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = kind == 'marker'
        ? s.width * 1.3
        : kind == 'pencil'
            ? s.width * 0.8
            : s.width
    ..color = kind == 'highlighter'
        ? base.withOpacity(0.35)
        : kind == 'pencil'
            ? base.withOpacity(0.85)
            : base;
  canvas.drawPath(path, paint);
}

void paintPaperBackground(
    Canvas canvas, Size size, String bg, int paper, bool hasImage) {
  canvas.drawRect(Offset.zero & size, Paint()..color = Color(paper));
  if (hasImage) return;
  final dark = Color(paper).computeLuminance() < 0.35;
  final lc = (dark ? Colors.white : Colors.black).withOpacity(dark ? 0.14 : 0.13);
  final line = Paint()
    ..color = lc
    ..strokeWidth = 1.2;
  final big = size.width > 2000;
  switch (bg) {
    case 'lined':
      for (double y = 84; y < size.height; y += 36) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
      if (!big) {
        canvas.drawLine(
            const Offset(80, 0),
            Offset(80, size.height),
            Paint()
              ..color = Colors.red.withOpacity(0.35)
              ..strokeWidth = 1.5);
      }
      break;
    case 'grid':
      for (double y = 0; y < size.height; y += 32) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
      for (double x = 0; x < size.width; x += 32) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      }
      break;
    case 'dotted':
      final step = big ? 48.0 : 32.0;
      final dots = <Offset>[];
      for (double y = step; y < size.height; y += step) {
        for (double x = step; x < size.width; x += step) {
          dots.add(Offset(x, y));
        }
      }
      canvas.drawPoints(
          ui.PointMode.points,
          dots,
          Paint()
            ..color = lc.withOpacity(0.5)
            ..strokeWidth = big ? 3.4 : 2.6
            ..strokeCap = StrokeCap.round);
      break;
    case 'cornell':
      final bottom = size.height * 0.82;
      for (double y = 100; y < bottom; y += 36) {
        canvas.drawLine(Offset(size.width * 0.28, y), Offset(size.width, y), line);
      }
      final strong = Paint()
        ..color = lc.withOpacity(0.5)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(size.width * 0.28, 0),
          Offset(size.width * 0.28, bottom), strong);
      canvas.drawLine(Offset(0, bottom), Offset(size.width, bottom), strong);
      canvas.drawLine(const Offset(0, 80), Offset(size.width, 80), strong);
      break;
    case 'music':
      for (double y = 110; y < size.height - 90; y += 130) {
        for (int i = 0; i < 5; i++) {
          canvas.drawLine(
              Offset(40, y + i * 14), Offset(size.width - 40, y + i * 14), line);
        }
      }
      break;
  }
}

class PaperPainter extends CustomPainter {
  final String bg;
  final int paper;
  final bool hasImage;
  PaperPainter(this.bg, this.paper, this.hasImage);

  @override
  void paint(Canvas canvas, Size size) =>
      paintPaperBackground(canvas, size, bg, paper, hasImage);

  @override
  bool shouldRepaint(covariant PaperPainter o) =>
      o.bg != bg || o.paper != paper || o.hasImage != hasImage;
}

class StrokesPainter extends CustomPainter {
  final List<StrokeData> strokes;
  final int version;
  StrokesPainter(this.strokes, this.version);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      drawStroke(canvas, s);
    }
  }

  @override
  bool shouldRepaint(covariant StrokesPainter o) => o.version != version;
}

class LivePainter extends CustomPainter {
  final DrawingController c;
  final double scale;
  LivePainter(this.c, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final hs = 1 / scale;
    if (c.active != null) drawStroke(canvas, c.active!);
    if (c.preview != null) drawStroke(canvas, c.preview!);

    final r = c.selectionRect();
    if (r != null) {
      canvas.drawRect(r, Paint()..color = kBrand.withOpacity(0.06));
      canvas.drawRect(
          r,
          Paint()
            ..color = kBrand
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * hs);
      final white = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * hs
        ..strokeCap = StrokeCap.round;
      void handle(Offset ctr, Color col) {
        canvas.drawCircle(ctr, 14 * hs, Paint()..color = col);
        canvas.drawCircle(
            ctr,
            14 * hs,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 * hs);
      }

      handle(r.topRight, Colors.red);
      final d = 5 * hs;
      canvas.drawLine(r.topRight + Offset(-d, -d), r.topRight + Offset(d, d), white);
      canvas.drawLine(r.topRight + Offset(-d, d), r.topRight + Offset(d, -d), white);
      final so = c.singleObject;
      if (so != null) {
        handle(r.bottomRight, kBrand);
        final b = r.bottomRight;
        canvas.drawLine(b + Offset(-d, d), b + Offset(d, -d), white);
        canvas.drawLine(b + Offset(-d, d), b + Offset(-d + 5 * hs, d), white);
        canvas.drawLine(b + Offset(-d, d), b + Offset(-d, d - 5 * hs), white);
        canvas.drawLine(b + Offset(d, -d), b + Offset(d - 5 * hs, -d), white);
        canvas.drawLine(b + Offset(d, -d), b + Offset(d, -d + 5 * hs), white);
        if (so.type == 'text' || so.type == 'sticky') {
          handle(r.topLeft, const Color(0xFF16A34A));
          final t = r.topLeft;
          canvas.drawLine(t + Offset(-d, d), t + Offset(d, -d), white);
          canvas.drawLine(t + Offset(-d, d), t + Offset(-d, d - 3 * hs), white);
          canvas.drawLine(t + Offset(-d, d), t + Offset(-d + 3 * hs, d), white);
        }
      }
    }

    if (c.lasso.length > 1) {
      final path = Path()..moveTo(c.lasso.first.dx, c.lasso.first.dy);
      for (final p in c.lasso.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, Paint()..color = kBrand.withOpacity(0.07));
      canvas.drawPath(
          path,
          Paint()
            ..color = kBrand
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * hs
            ..strokeJoin = StrokeJoin.round);
    }

    if (c.laser.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final l in c.laser) {
        final a = 1 - (now - l.ms) / 700.0;
        if (a <= 0) continue;
        canvas.drawCircle(l.pos, (7 + 10 * a) * hs,
            Paint()..color = Colors.red.withOpacity(0.28 * a));
        canvas.drawCircle(
            l.pos, 5 * hs, Paint()..color = Colors.red.withOpacity(0.9 * a));
      }
    }
  }

  @override
  bool shouldRepaint(covariant LivePainter o) => true;
}

Widget buildObjectView(PageObject o) {
  switch (o.type) {
    case 'image':
      return Image.file(
        File(o.path),
        fit: BoxFit.fill,
        cacheWidth: 1600,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey.shade300,
          child: const Icon(Icons.broken_image),
        ),
      );
    case 'text':
      return ClipRect(
        child: Text(
          o.text,
          style: TextStyle(color: Color(o.color), fontSize: o.fontSize, height: 1.25),
        ),
      );
    case 'sticky':
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Color(o.color),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: ClipRect(
          child: Text(
            o.text,
            style: TextStyle(color: Colors.black87, fontSize: o.fontSize, height: 1.25),
          ),
        ),
      );
    default:
      return FittedBox(
        fit: BoxFit.contain,
        child: Text(o.text, style: const TextStyle(fontSize: 100)),
      );
  }
}

void paintObjectStatic(Canvas canvas, PageObject o, ui.Image? img) {
  switch (o.type) {
    case 'image':
      if (img != null) {
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          o.rect,
          Paint()..filterQuality = FilterQuality.high,
        );
      }
      break;
    case 'text':
      final tp = TextPainter(
        text: TextSpan(
            text: o.text,
            style: TextStyle(color: Color(o.color), fontSize: o.fontSize, height: 1.25)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(10.0, o.w));
      tp.paint(canvas, Offset(o.x, o.y));
      break;
    case 'sticky':
      canvas.drawRRect(RRect.fromRectAndRadius(o.rect, const Radius.circular(6)),
          Paint()..color = Color(o.color));
      final tp = TextPainter(
        text: TextSpan(
            text: o.text,
            style: TextStyle(color: Colors.black87, fontSize: o.fontSize, height: 1.25)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(10.0, o.w - 28));
      canvas.save();
      canvas.clipRect(o.rect);
      tp.paint(canvas, Offset(o.x + 14, o.y + 14));
      canvas.restore();
      break;
    default:
      final tp = TextPainter(
        text: TextSpan(text: o.text, style: TextStyle(fontSize: o.h * 0.8)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(o.x + (o.w - tp.width) / 2, o.y + (o.h - tp.height) / 2));
  }
}

Rect? contentBounds(NotePage pg) {
  Rect? r;
  for (final s in pg.strokes) {
    r = r == null ? s.bounds : r.expandToInclude(s.bounds);
  }
  for (final o in pg.objects) {
    r = r == null ? o.rect : r.expandToInclude(o.rect);
  }
  return r;
}

Rect pageExportRect(NotePage pg) {
  final full = Rect.fromLTWH(0, 0, pg.w, pg.h);
  if (!pg.isBoard) return full;
  final b = contentBounds(pg);
  if (b == null) return Rect.fromLTWH(pg.w / 2 - 800, pg.h / 2 - 600, 1600, 1200);
  var r = b.inflate(80).intersect(full);
  if (r.width < 600) r = Rect.fromCenter(center: r.center, width: 600, height: r.height);
  if (r.height < 450) r = Rect.fromCenter(center: r.center, width: r.width, height: 450);
  return r.intersect(full);
}

Future<ui.Image?> loadUiImage(String path) async {
  try {
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
    final f = await codec.getNextFrame();
    return f.image;
  } catch (_) {
    return null;
  }
}

class RenderedPage {
  final Uint8List bytes;
  final double w, h;
  RenderedPage(this.bytes, this.w, this.h);
}

Future<RenderedPage> renderPage(NotePage pg, {double scale = 2}) async {
  final region = pageExportRect(pg);
  final sc = pg.isBoard
      ? math.min(scale, 4000 / math.max(region.width, region.height))
      : scale;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(sc);
  canvas.translate(-region.left, -region.top);
  canvas.clipRect(region);
  paintPaperBackground(
      canvas, Size(pg.w, pg.h), pg.background, pg.paper, pg.bgImage != null);
  if (pg.bgImage != null) {
    final bg = await loadUiImage(pg.bgImage!);
    if (bg != null) {
      canvas.drawImageRect(
        bg,
        Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
        Rect.fromLTWH(0, 0, pg.w, pg.h),
        Paint()..filterQuality = FilterQuality.high,
      );
      bg.dispose();
    }
  }
  for (final o in pg.objects) {
    ui.Image? img;
    if (o.type == 'image') img = await loadUiImage(o.path);
    paintObjectStatic(canvas, o, img);
    img?.dispose();
  }
  for (final s in pg.strokes) {
    drawStroke(canvas, s);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(
      (region.width * sc).round(), (region.height * sc).round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return RenderedPage(data!.buffer.asUint8List(), region.width, region.height);
}

Future<Uint8List> buildPdf(List<NotePage> pages) async {
  final doc = pw.Document();
  final sc = pages.length > 30 ? 1.3 : 2.0;
  for (final pg in pages) {
    final r = await renderPage(pg, scale: sc);
    final img = pw.MemoryImage(r.bytes);
    final fmt = PdfPageFormat(595.28, 595.28 * r.h / r.w);
    doc.addPage(
      pw.Page(
        pageFormat: fmt,
        margin: pw.EdgeInsets.zero,
        build: (_) =>
            pw.FullPage(ignoreMargins: true, child: pw.Image(img, fit: pw.BoxFit.fill)),
      ),
    );
  }
  return doc.save();
}

Future<bool> saveBytesAs(String fileName, Uint8List bytes) async {
  final mobile = Platform.isAndroid || Platform.isIOS;
  var path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save',
    fileName: fileName,
    bytes: mobile ? bytes : null,
  );
  if (path == null) return false;
  if (!mobile) {
    final ext = fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.')) : '';
    if (ext.isNotEmpty && !path.toLowerCase().endsWith(ext)) path += ext;
    await File(path).writeAsBytes(bytes);
  }
  return true;
}

// ─────────────────────────────────────────────────────────────
// THUMBNAILS
// ─────────────────────────────────────────────────────────────
class _ThumbPainter extends CustomPainter {
  final NotePage page;
  final Rect region;
  final double s;
  final bool ink;
  _ThumbPainter(this.page, this.region, this.s, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(s);
    canvas.translate(-region.left, -region.top);
    if (!ink) {
      paintPaperBackground(canvas, Size(page.w, page.h), page.background,
          page.paper, page.bgImage != null);
      for (final o in page.objects) {
        if (o.type != 'image') paintObjectStatic(canvas, o, null);
      }
    } else {
      for (final st in page.strokes) {
        drawStroke(canvas, st);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter o) => true;
}

class PageThumb extends StatelessWidget {
  final NotePage page;
  const PageThumb({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    final r = pageExportRect(page);
    return AspectRatio(
      aspectRatio: r.width / r.height,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black12),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (ctx, cons) {
          final s = cons.maxWidth / r.width;
          return Stack(
            children: [
              Positioned.fill(
                  child: CustomPaint(painter: _ThumbPainter(page, r, s, false))),
              if (page.bgImage != null)
                Positioned.fill(
                  child: Image.file(File(page.bgImage!),
                      fit: BoxFit.fill,
                      cacheWidth: 280,
                      errorBuilder: (_, __, ___) => const SizedBox()),
                ),
              for (final o in page.objects.where((o) => o.type == 'image'))
                Positioned(
                  left: (o.x - r.left) * s,
                  top: (o.y - r.top) * s,
                  width: o.w * s,
                  height: o.h * s,
                  child: Image.file(File(o.path),
                      fit: BoxFit.fill,
                      cacheWidth: 200,
                      errorBuilder: (_, __, ___) => const SizedBox()),
                ),
              Positioned.fill(
                  child: CustomPaint(painter: _ThumbPainter(page, r, s, true))),
            ],
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CANVAS VIEW (zoom, pan, tools)
// ─────────────────────────────────────────────────────────────
enum _Mode { none, tool, pinch, panMouse }

enum _Sel { none, move, resize, lasso }

class CanvasView extends StatefulWidget {
  final DrawingController controller;
  final NotePage page;
  final NotesProvider provider;
  final void Function(String type, Offset pos) onCreateText;
  final void Function(PageObject o) onEditObject;
  final VoidCallback onChanged;

  const CanvasView({
    super.key,
    required this.controller,
    required this.page,
    required this.provider,
    required this.onCreateText,
    required this.onEditObject,
    required this.onChanged,
  });

  @override
  State<CanvasView> createState() => CanvasViewState();
}

class CanvasViewState extends State<CanvasView> {
  double _scale = 1;
  Offset _offset = Offset.zero;
  String? _fitPageId;
  Size _view = Size.zero;

  final Map<int, Offset> _ptrs = {};
  _Mode _mode = _Mode.none;
  bool _ignore = false;
  bool _stylusDown = false;
  Offset _focal0 = Offset.zero;
  Offset _offset0 = Offset.zero;
  double _dist0 = 1;
  double _scale0 = 1;
  Offset _lastLocal = Offset.zero;
  double _pzLast = 1;

  ToolType _cur = ToolType.pen;
  Offset _startQ = Offset.zero;
  Offset _lastQ = Offset.zero;
  bool _moved = false;
  bool _snapped = false;
  double _simP = 0.9;
  Timer? _holdTimer;
  Timer? _laserTimer;
  _Sel _sel = _Sel.none;
  int _lastTapMs = 0;

  double get _minScale => widget.page.isBoard ? 0.08 : 0.3;
  double get _maxScale => 6;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _laserTimer?.cancel();
    super.dispose();
  }

  Offset _toPage(Offset local) => (local - _offset) / _scale;

  Offset viewCenter() => _toPage(Offset(_view.width / 2, _view.height / 2));

  void fit() => setState(() {
        _fitPageId = null;
      });

  void _ensureFit() {
    final pg = widget.page;
    if (_fitPageId == pg.id || _view.width < 10) return;
    _fitPageId = pg.id;
    if (pg.isBoard) {
      _scale = (_view.width / 1500).clamp(0.2, 1.0).toDouble();
      final b = contentBounds(pg);
      final c = b?.center ?? Offset(pg.w / 2, pg.h / 2);
      _offset = Offset(_view.width / 2, _view.height / 2) - c * _scale;
    } else {
      _scale = ((_view.width - 24) / pg.w).clamp(0.2, 2.0).toDouble();
      _offset = Offset((_view.width - pg.w * _scale) / 2,
          math.max(12.0, (_view.height - pg.h * _scale) / 2));
    }
  }

  void _clampOffset() {
    final w = widget.page.w * _scale;
    final h = widget.page.h * _scale;
    const m = 80.0;
    _offset = Offset(
      _offset.dx.clamp(m - w, math.max(m - w, _view.width - m)).toDouble(),
      _offset.dy.clamp(m - h, math.max(m - h, _view.height - m)).toDouble(),
    );
  }

  // ── pointer plumbing ──
  void _down(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse &&
        (e.buttons & (kMiddleMouseButton | kSecondaryMouseButton)) != 0) {
      _mode = _Mode.panMouse;
      _lastLocal = e.localPosition;
      return;
    }
    final isStylus = e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus;
    if (_stylusDown && e.kind == PointerDeviceKind.touch) return;
    if (isStylus) _stylusDown = true;
    _ptrs[e.pointer] = e.localPosition;
    if (_ptrs.length >= 2) {
      _cancelTool();
      _mode = _Mode.pinch;
      _ignore = true;
      final p = _ptrs.values.toList();
      _dist0 = math.max(1.0, (p[0] - p[1]).distance);
      _scale0 = _scale;
      _offset0 = _offset;
      _focal0 = (p[0] + p[1]) / 2;
      return;
    }
    if (_ignore) return;
    _mode = _Mode.tool;
    _toolDown(e);
  }

  void _move(PointerMoveEvent e) {
    if (_mode == _Mode.panMouse) {
      setState(() {
        _offset += e.localPosition - _lastLocal;
        _lastLocal = e.localPosition;
        _clampOffset();
      });
      return;
    }
    if (!_ptrs.containsKey(e.pointer)) return;
    _ptrs[e.pointer] = e.localPosition;
    if (_mode == _Mode.pinch && _ptrs.length >= 2) {
      final p = _ptrs.values.toList();
      final dist = math.max(1.0, (p[0] - p[1]).distance);
      final focal = (p[0] + p[1]) / 2;
      final ns = (_scale0 * dist / _dist0).clamp(_minScale, _maxScale).toDouble();
      final pagePt = (_focal0 - _offset0) / _scale0;
      setState(() {
        _scale = ns;
        _offset = focal - pagePt * ns;
        _clampOffset();
      });
    } else if (_mode == _Mode.tool) {
      _toolMove(e);
    }
  }

  void _up(PointerUpEvent e) {
    if (_mode == _Mode.panMouse) {
      _mode = _Mode.none;
      return;
    }
    if (e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      _stylusDown = false;
    }
    final had = _ptrs.remove(e.pointer) != null;
    if (!had) return;
    if (_mode == _Mode.tool) {
      _toolUp(e);
      _mode = _Mode.none;
    } else if (_mode == _Mode.pinch && _ptrs.length < 2) {
      _mode = _Mode.none;
    }
    if (_ptrs.isEmpty) {
      _ignore = false;
      _mode = _Mode.none;
    }
  }

  void _cancel(PointerCancelEvent e) {
    _stylusDown = false;
    if (_ptrs.remove(e.pointer) != null && _mode == _Mode.tool) _cancelTool();
    if (_ptrs.isEmpty) {
      _ignore = false;
      _mode = _Mode.none;
    }
  }

  void _signal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    if (HardwareKeyboard.instance.isControlPressed) {
      final f = math.exp(-e.scrollDelta.dy / 400);
      final ns = (_scale * f).clamp(_minScale, _maxScale).toDouble();
      final pagePt = (e.localPosition - _offset) / _scale;
      setState(() {
        _scale = ns;
        _offset = e.localPosition - pagePt * ns;
        _clampOffset();
      });
    } else {
      setState(() {
        _offset -= e.scrollDelta;
        _clampOffset();
      });
    }
  }

  void _pzStart(PointerPanZoomStartEvent e) => _pzLast = 1;

  void _pzUpdate(PointerPanZoomUpdateEvent e) {
    final ns = (_scale * (e.scale / _pzLast)).clamp(_minScale, _maxScale).toDouble();
    final pagePt = (e.localPosition - _offset) / _scale;
    setState(() {
      _scale = ns;
      _offset = e.localPosition - pagePt * ns + e.panDelta;
      _clampOffset();
    });
    _pzLast = e.scale;
  }

  // ── tools ──
  double get _eraseR => (16 / _scale).clamp(6.0, 60.0).toDouble();

  double _pressure(PointerEvent e) {
    if (e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus) {
      return e.pressure.clamp(0.15, 1.0).toDouble();
    }
    return _simP;
  }

  void _cancelTool() {
    _holdTimer?.cancel();
    widget.controller.cancelStroke();
    widget.controller.setPreview(null);
    widget.controller.lasso = [];
    _sel = _Sel.none;
  }

  void _restartHold() {
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 650), () {
      final c = widget.controller;
      final a = c.active;
      if (a == null || _snapped) return;
      final snapped = recognizeShape(a.points);
      if (snapped != null) {
        c.replaceActive(snapped);
        _snapped = true;
        HapticFeedback.selectionClick();
      }
    });
  }

  void _toolDown(PointerDownEvent e) {
    final p = widget.provider;
    final c = widget.controller;
    final q = _toPage(e.localPosition);
    _cur = e.kind == PointerDeviceKind.invertedStylus ? ToolType.eraser : p.tool;
    _startQ = q;
    _lastQ = q;
    _moved = false;
    _snapped = false;
    _simP = 0.9;
    switch (_cur) {
      case ToolType.pen:
      case ToolType.highlighter:
        final hl = _cur == ToolType.highlighter;
        c.beginStroke(StrokeData(
          points: [StrokePoint(q.dx, q.dy, _pressure(e))],
          color: hl ? p.highlightColor.value : p.penColor.value,
          width: hl ? p.highlightWidth : p.penWidth,
          kind: hl ? 'highlighter' : p.penKind,
        ));
        _restartHold();
        break;
      case ToolType.eraser:
        c.beginErase();
        c.eraseAlong(q, q, _eraseR);
        break;
      case ToolType.select:
        _selDown(q);
        break;
      case ToolType.laser:
        c.addLaser(q);
        _laserTimer?.cancel();
        _laserTimer = Timer.periodic(const Duration(milliseconds: 40), (t) {
          if (c.laser.isEmpty) {
            t.cancel();
          } else {
            c.pruneLaser();
          }
        });
        break;
      case ToolType.shape:
      case ToolType.text:
      case ToolType.sticky:
        break;
    }
  }

  void _toolMove(PointerMoveEvent e) {
    final p = widget.provider;
    final c = widget.controller;
    final q = _toPage(e.localPosition);
    if ((q - _startQ).distance * _scale > 5) _moved = true;
    switch (_cur) {
      case ToolType.pen:
      case ToolType.highlighter:
        if (_snapped) break;
        final dist = (q - _lastQ).distance * _scale;
        _simP = _simP * 0.6 + (1.0 - dist / 45).clamp(0.45, 1.0).toDouble() * 0.4;
        c.extendStroke(StrokePoint(q.dx, q.dy, _pressure(e)));
        _lastQ = q;
        _restartHold();
        break;
      case ToolType.eraser:
        c.eraseAlong(_lastQ, q, _eraseR);
        _lastQ = q;
        break;
      case ToolType.shape:
        if (_moved) {
          c.setPreview(StrokeData(
            points: shapePoints(p.shapeType, _startQ, q),
            color: p.penColor.value,
            width: p.penWidth,
            kind: 'ballpoint',
          ));
        }
        break;
      case ToolType.select:
        _selMove(q);
        break;
      case ToolType.laser:
        c.addLaser(q);
        break;
      case ToolType.text:
      case ToolType.sticky:
        break;
    }
  }

  void _toolUp(PointerUpEvent e) {
    final p = widget.provider;
    final c = widget.controller;
    final q = _toPage(e.localPosition);
    switch (_cur) {
      case ToolType.pen:
      case ToolType.highlighter:
        _holdTimer?.cancel();
        if (!_snapped && p.autoShape && _cur == ToolType.pen) {
          final a = c.active;
          if (a != null) {
            final s = recognizeShape(a.points);
            if (s != null) c.replaceActive(s);
          }
        }
        c.endStroke();
        widget.onChanged();
        break;
      case ToolType.eraser:
        widget.onChanged();
        break;
      case ToolType.shape:
        if (_moved) {
          final pts = shapePoints(p.shapeType, _startQ, q);
          c.setPreview(null);
          if (pts.length > 1) {
            c.addStroke(StrokeData(
                points: pts,
                color: p.penColor.value,
                width: p.penWidth,
                kind: 'ballpoint'));
          }
          widget.onChanged();
        }
        break;
      case ToolType.text:
      case ToolType.sticky:
        if (!_moved) {
          widget.onCreateText(_cur == ToolType.text ? 'text' : 'sticky', q);
        }
        break;
      case ToolType.select:
        _selUp(q);
        break;
      case ToolType.laser:
        break;
    }
  }

  // ── select tool ──
  void _selDown(Offset q) {
    final c = widget.controller;
    _sel = _Sel.none;
    if (c.hasSelection) {
      final r = c.selectionRect()!;
      final hr = 22 / _scale;
      if ((q - r.topRight).distance < hr) {
        c.deleteSelection();
        widget.onChanged();
        return;
      }
      final so = c.singleObject;
      if (so != null) {
        if ((q - r.bottomRight).distance < hr) {
          c.beginMove();
          _sel = _Sel.resize;
          return;
        }
        if ((so.type == 'text' || so.type == 'sticky') &&
            (q - r.topLeft).distance < hr) {
          widget.onEditObject(so);
          return;
        }
      }
      if (r.inflate(4 / _scale).contains(q)) {
        c.beginMove();
        _sel = _Sel.move;
        return;
      }
    }
    final o = c.objectAt(q);
    if (o != null) {
      c.selectOnly(object: o);
      c.beginMove();
      _sel = _Sel.move;
      return;
    }
    final s = c.strokeAt(q, 12 / _scale);
    if (s != null) {
      c.selectOnly(stroke: s);
      c.beginMove();
      _sel = _Sel.move;
      return;
    }
    c.clearSelection();
    c.lasso = [q];
    _sel = _Sel.lasso;
  }

  void _selMove(Offset q) {
    final c = widget.controller;
    switch (_sel) {
      case _Sel.move:
        if (_moved) {
          c.moveSelection(q - _lastQ);
          _lastQ = q;
        }
        break;
      case _Sel.resize:
        c.resizeSingle(q);
        break;
      case _Sel.lasso:
        c.lasso.add(q);
        c.touch();
        break;
      case _Sel.none:
        break;
    }
  }

  void _selUp(Offset q) {
    final c = widget.controller;
    switch (_sel) {
      case _Sel.lasso:
        c.finishLasso();
        break;
      case _Sel.move:
        if (_moved) {
          widget.onChanged();
        } else {
          final so = c.singleObject;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (so != null &&
              (so.type == 'text' || so.type == 'sticky') &&
              now - _lastTapMs < 400) {
            widget.onEditObject(so);
          }
          _lastTapMs = now;
        }
        break;
      case _Sel.resize:
        widget.onChanged();
        break;
      case _Sel.none:
        break;
    }
    _sel = _Sel.none;
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    final pg = widget.page;
    final c = widget.controller;
    return LayoutBuilder(builder: (ctx, cons) {
      _view = Size(cons.maxWidth, cons.maxHeight);
      _ensureFit();
      return ClipRect(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _cancel,
          onPointerSignal: _signal,
          onPointerPanZoomStart: _pzStart,
          onPointerPanZoomUpdate: _pzUpdate,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: _offset.dx,
                top: _offset.dy,
                width: pg.w,
                height: pg.h,
                child: Transform.scale(
                  scale: _scale,
                  alignment: Alignment.topLeft,
                  child: IgnorePointer(
                    child: Container(
                      width: pg.w,
                      height: pg.h,
                      decoration: const BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                              color: Color(0x44000000),
                              blurRadius: 30,
                              offset: Offset(0, 10)),
                        ],
                      ),
                      child: AnimatedBuilder(
                        animation: c,
                        builder: (context, _) => Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: PaperPainter(
                                      pg.background, pg.paper, pg.bgImage != null),
                                ),
                              ),
                            ),
                            if (pg.bgImage != null)
                              Positioned.fill(
                                child: Image.file(
                                  File(pg.bgImage!),
                                  fit: BoxFit.fill,
                                  cacheWidth: 1400,
                                  errorBuilder: (_, __, ___) => const SizedBox(),
                                ),
                              ),
                            for (final o in c.objects)
                              Positioned(
                                left: o.x,
                                top: o.y,
                                width: o.w,
                                height: o.h,
                                child: buildObjectView(o),
                              ),
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: StrokesPainter(c.strokes, c.strokeVer),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: CustomPaint(painter: LivePainter(c, _scale)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────
// AI
// ─────────────────────────────────────────────────────────────
class AiService {
  final String apiKey;
  final String baseUrl;
  final String model;

  AiService({required this.apiKey, required this.baseUrl, required this.model});

  Future<String> _post(List<Map<String, dynamic>> messages) async {
    if (apiKey.isEmpty) {
      throw Exception('API key not set. Add it under "API settings" below.');
    }
    final url = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r"/+$"), "")}/chat/completions');
    final res = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({'model': model, 'messages': messages, 'temperature': 0.4}),
    );
    if (res.statusCode != 200) {
      throw Exception('AI error ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return data['choices'][0]['message']['content'] as String;
  }

  Future<String> chat(String prompt) => _post([
        {
          'role': 'system',
          'content': 'You are a helpful note-taking assistant. Be concise and clear.'
        },
        {'role': 'user', 'content': prompt},
      ]);

  Future<String> chatWithImage(String prompt, Uint8List png) => _post([
        {
          'role': 'system',
          'content': 'You are a helpful note-taking assistant. Be concise and clear.'
        },
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,${base64Encode(png)}'}
            },
          ],
        },
      ]);
}

class AiPanel extends StatefulWidget {
  final NotesProvider provider;
  final Future<Uint8List> Function() getPagePng;
  final void Function(String text) onInsert;
  final void Function(String text) onSaveText;

  const AiPanel({
    super.key,
    required this.provider,
    required this.getPagePng,
    required this.onInsert,
    required this.onSaveText,
  });

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  final _promptCtrl = TextEditingController();
  final _outputCtrl = TextEditingController();
  late final TextEditingController _keyCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _modelCtrl;
  bool _loading = false;
  bool _useImage = true;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.provider.apiKey);
    _urlCtrl = TextEditingController(text: widget.provider.baseUrl);
    _modelCtrl = TextEditingController(text: widget.provider.model);
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    _outputCtrl.dispose();
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(String instruction, {bool forceImage = false}) async {
    if (instruction.trim().isEmpty) return;
    setState(() => _loading = true);
    _outputCtrl.text = 'Thinking…';
    try {
      final p = widget.provider;
      final svc = AiService(apiKey: p.apiKey, baseUrl: p.baseUrl, model: p.model);
      String result;
      if (_useImage || forceImage) {
        final png = await widget.getPagePng();
        result = await svc.chatWithImage(instruction, png);
      } else {
        final text = p.currentPage?.textContent ?? '';
        if (text.trim().isEmpty) {
          throw Exception(
              'This page has no typed notes. Switch to "Page image" or add typed notes.');
        }
        result = await svc.chat('$instruction\n\n$text');
      }
      _outputCtrl.text = result;
    } catch (e) {
      _outputCtrl.text = 'Error: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
                16, MediaQuery.of(context).padding.top + 14, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [kBrand, kBrand2]),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white),
                const SizedBox(width: 10),
                Text('AI assistant',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.white)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Page image')),
                    ButtonSegment(value: false, label: Text('Typed notes')),
                  ],
                  selected: {_useImage},
                  onSelectionChanged: (s) => setState(() => _useImage = s.first),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(
                        'Read handwriting',
                        () => _run(
                            'Transcribe all handwriting and text on this page exactly as written. Output only the transcription.',
                            forceImage: true)),
                    _chip(
                        'Solve math',
                        () => _run('Solve the math problems on this page step by step.',
                            forceImage: true)),
                    _chip('Summarize', () => _run('Summarize these notes concisely.')),
                    _chip('Improve',
                        () => _run('Rewrite these notes with better clarity and structure.')),
                    _chip('Flashcards',
                        () => _run('Create Q&A flashcards from these notes.')),
                    _chip(
                        'Quiz me',
                        () => _run(
                            'Write a 5-question quiz with answers based on these notes.')),
                    _chip('Outline', () => _run('Create a clear outline from these notes.')),
                    _chip('Key ideas',
                        () => _run('Extract the key ideas from these notes.')),
                    _chip('Translate', () {
                      final lang = _promptCtrl.text.trim().isEmpty
                          ? 'English'
                          : _promptCtrl.text.trim();
                      _run('Translate these notes into $lang.');
                    }),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _promptCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Ask anything, or type a language for Translate…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: const Text('Send'),
                  onPressed: _loading ? null : () => _run(_promptCtrl.text),
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(minHeight: 150),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _outputCtrl,
                    maxLines: null,
                    minLines: 8,
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.text_fields),
                      label: const Text('Add to page'),
                      onPressed: () {
                        if (_outputCtrl.text.isNotEmpty) widget.onInsert(_outputCtrl.text);
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.search),
                      label: const Text('Save for search'),
                      onPressed: () {
                        if (_outputCtrl.text.isEmpty) return;
                        widget.onSaveText(_outputCtrl.text);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Saved')));
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _outputCtrl.text));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Copied')));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                Text('API settings', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                const Text(
                  'Page image needs a vision model such as gpt-4o-mini.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _keyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'API key', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Base URL', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _modelCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Model', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      widget.provider.saveApiSettings(
                        key: _keyCtrl.text.trim(),
                        url: _urlCtrl.text.trim(),
                        modelName: _modelCtrl.text.trim(),
                      );
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Saved')));
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) =>
      ActionChip(label: Text(label), onPressed: _loading ? null : onTap);
}

// ─────────────────────────────────────────────────────────────
// HOME / LIBRARY
// ─────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';
  bool _list = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<NotesProvider>();
    final isWide = MediaQuery.of(context).size.width >= 900;
    final docs = p.visibleNotebooks(_query);
    final folder = findFirst(p.folders, (f) => f.id == p.folderFilter);

    return Scaffold(
      key: _scaffoldKey,
      drawer: isWide ? null : Drawer(child: _sidebar(p, true)),
      floatingActionButton: isWide
          ? null
          : FloatingActionButton.extended(
              backgroundColor: kBrand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Create'),
              onPressed: () => _createMenu(p),
            ),
      body: Row(
        children: [
          if (isWide) SizedBox(width: 260, child: _sidebar(p, false)),
          Expanded(
            child: Column(
              children: [
                _topBar(p, isWide),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          folder?.name ?? 'All notes',
                          style: Theme.of(context).textTheme.headlineSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: _list ? 'Grid view' : 'List view',
                        icon: Icon(_list ? Icons.grid_view : Icons.view_list),
                        onPressed: () => setState(() => _list = !_list),
                      ),
                      if (isWide)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: kBrand),
                          icon: const Icon(Icons.add),
                          label: const Text('Create'),
                          onPressed: () => _createMenu(p),
                        ),
                    ],
                  ),
                ),
                Expanded(child: _content(p, docs)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(NotesProvider p, bool isWide) {
    return Container(
      color: kBar,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Row(
            children: [
              if (!isWide) ...[
                IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                const AppLogo(size: 30),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Search notes…',
                    hintStyle: const TextStyle(color: Colors.black45),
                    prefixIcon: const Icon(Icons.search),
                    prefixIconColor: Colors.black54,
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              IconButton(
                tooltip: 'Dark mode',
                icon: Icon(p.darkMode ? Icons.light_mode : Icons.dark_mode,
                    color: Colors.white),
                onPressed: () => p.setDarkMode(!p.darkMode),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebar(NotesProvider p, bool drawer) {
    final cs = Theme.of(context).colorScheme;
    Widget item(IconData icon, Color color, String label, int count, bool sel,
        VoidCallback onTap,
        {Widget? trailing}) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: sel ? kBrand.withOpacity(0.14) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(icon, color: color),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: trailing ?? Text('$count'),
          onTap: () {
            onTap();
            if (drawer) Navigator.pop(context);
          },
        ),
      );
    }

    return Material(
      color: cs.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  const AppLogo(size: 40),
                  const SizedBox(width: 12),
                  Text('NoteSmart',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  item(Icons.library_books_outlined, kBrand, 'All notes',
                      p.notebooks.length, p.folderFilter == null,
                      () => p.setFolder(null)),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 14, 16, 4),
                    child: Text('FOLDERS',
                        style: TextStyle(fontSize: 11, letterSpacing: 1)),
                  ),
                  for (final f in p.folders)
                    item(
                      Icons.folder,
                      Color(f.color),
                      f.name,
                      p.notebooks.where((n) => n.folderId == f.id).length,
                      p.folderFilter == f.id,
                      () => p.setFolder(f.id),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, size: 20),
                        onSelected: (v) => _folderAction(p, f, v),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'color', child: Text('Change color')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.create_new_folder_outlined),
                    title: const Text('New folder'),
                    onTap: () {
                      if (drawer) Navigator.pop(context);
                      _newFolder(p);
                    },
                  ),
                ],
              ),
            ),
            SwitchListTile(
              dense: true,
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark mode'),
              value: p.darkMode,
              onChanged: (v) => p.setDarkMode(v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(NotesProvider p, List<Notebook> docs) {
    if (docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 72),
              const SizedBox(height: 16),
              Text(_query.isEmpty ? 'Start your first note' : 'No matches',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('Create a notebook, whiteboard, or import a PDF.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (_list) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
        itemCount: docs.length,
        itemBuilder: (ctx, i) {
          final nb = docs[i];
          return ListTile(
            leading: SizedBox(
                width: 44,
                height: 56,
                child: Center(child: PageThumb(page: nb.pages.first))),
            title: Text(nb.name),
            subtitle: Text(
                '${kindLabel(nb.kind)} · ${nb.pages.length} pages · ${_fmtDate(nb.updatedAt)}'),
            trailing: _docMenu(p, nb),
            onTap: () => _open(p, nb),
          );
        },
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.7,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: docs.length,
      itemBuilder: (ctx, i) => _docCard(p, docs[i]),
    );
  }

  Widget _docCard(NotesProvider p, Notebook nb) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(p, nb),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color(nb.color).withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 10,
                        offset: Offset(0, 4)),
                  ],
                ),
                child: PageThumb(page: nb.pages.first),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(kindIcon(nb.kind), size: 16, color: Color(nb.color)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(nb.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              _docMenu(p, nb),
            ],
          ),
          Text('${nb.pages.length} pages · ${_fmtDate(nb.updatedAt)}',
              style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _docMenu(NotesProvider p, Notebook nb) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) {
        switch (v) {
          case 'rename':
            _rename(p, nb);
            break;
          case 'move':
            _move(p, nb);
            break;
          case 'delete':
            _delete(p, nb);
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'move', child: Text('Move to folder')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  void _open(NotesProvider p, Notebook nb) {
    p.openNotebook(nb);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditorScreen()));
  }

  void _createMenu(NotesProvider p) {
    showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('New notebook'),
              subtitle: const Text('Pages with ruled, grid, dotted and more'),
              onTap: () {
                Navigator.pop(sheet);
                _newDoc(p, 'notebook');
              },
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('New whiteboard'),
              subtitle: const Text('Big canvas to pan and zoom'),
              onTap: () {
                Navigator.pop(sheet);
                _newDoc(p, 'board');
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Import PDF'),
              subtitle: const Text('Annotate slides, papers and worksheets'),
              onTap: () {
                Navigator.pop(sheet);
                _importPdf(p);
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New folder'),
              onTap: () {
                Navigator.pop(sheet);
                _newFolder(p);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newDoc(NotesProvider p, String kind) async {
    final nameCtrl =
        TextEditingController(text: kind == 'board' ? 'Whiteboard' : 'Notebook');
    String template = 'lined';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setS) => AlertDialog(
          title: Text(kind == 'board' ? 'New whiteboard' : 'New notebook'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              if (kind == 'notebook') ...[
                const SizedBox(height: 14),
                const Text('Template'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final t in const [
                      'lined',
                      'blank',
                      'grid',
                      'dotted',
                      'cornell',
                      'music'
                    ])
                      ChoiceChip(
                        label: Text(t[0].toUpperCase() + t.substring(1)),
                        selected: template == t,
                        onSelected: (_) => setS(() => template = t),
                      ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim().isEmpty ? 'Untitled' : nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || !mounted) return;
    final nb = p.createNotebook(name: name, kind: kind, template: template);
    _open(p, nb);
  }

  Future<void> _importPdf(NotesProvider p) async {
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (res == null || res.files.isEmpty || res.files.single.path == null) return;
    final f = res.files.single;
    var name = f.name;
    if (name.toLowerCase().endsWith('.pdf')) name = name.substring(0, name.length - 4);
    if (!mounted) return;
    final progress = ValueNotifier<int>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Importing PDF'),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, n, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(n == 0 ? 'Reading pages…' : 'Imported $n pages'),
            ],
          ),
        ),
      ),
    );
    try {
      final nb = await p.importPdf(f.path!, name, (n) => progress.value = n);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) _open(p, nb);
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(SnackBar(content: Text('Could not import PDF: $e')));
    }
    progress.dispose();
  }

  Future<String?> _nameDialog(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    return (r == null || r.isEmpty) ? null : r;
  }

  Future<void> _newFolder(NotesProvider p) async {
    final n = await _nameDialog('New folder', '');
    if (n != null) p.addFolder(n);
  }

  Future<void> _rename(NotesProvider p, Notebook nb) async {
    final n = await _nameDialog('Rename', nb.name);
    if (n != null) p.renameNotebook(nb.id, n);
  }

  Future<void> _move(NotesProvider p, Notebook nb) async {
    await showDialog(
      context: context,
      builder: (dctx) => SimpleDialog(
        title: const Text('Move to folder'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              p.moveNotebook(nb.id, null);
              Navigator.pop(dctx);
            },
            child: const Text('No folder'),
          ),
          for (final f in p.folders)
            SimpleDialogOption(
              onPressed: () {
                p.moveNotebook(nb.id, f.id);
                Navigator.pop(dctx);
              },
              child: Row(children: [
                Icon(Icons.folder, color: Color(f.color)),
                const SizedBox(width: 10),
                Text(f.name),
              ]),
            ),
        ],
      ),
    );
  }

  Future<void> _delete(NotesProvider p, Notebook nb) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('"${nb.name}" and all its pages will be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) p.deleteNotebook(nb.id);
  }

  Future<void> _folderAction(NotesProvider p, Folder f, String v) async {
    if (v == 'rename') {
      final n = await _nameDialog('Rename folder', f.name);
      if (n != null) p.renameFolder(f.id, n);
    } else if (v == 'color') {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Folder color'),
          content: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in kFolderColors)
                GestureDetector(
                  onTap: () {
                    p.recolorFolder(f.id, c);
                    Navigator.pop(dctx);
                  },
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Color(c),
                    child: f.color == c
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      );
    } else if (v == 'delete') {
      p.deleteFolder(f.id);
    }
  }
}

// ─────────────────────────────────────────────────────────────
// EDITOR
// ─────────────────────────────────────────────────────────────
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _controller = DrawingController();
  final _canvasKey = GlobalKey<CanvasViewState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _textCtrl = TextEditingController();
  bool _showPages = false;
  bool _showAi = false;
  bool _textMode = false;
  bool _presenting = false;
  ToolType _prevTool = ToolType.pen;
  String? _lastPageId;

  @override
  void dispose() {
    _controller.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _loadPageIfNeeded(NotePage page) {
    if (_lastPageId != page.id) {
      _lastPageId = page.id;
      _controller.loadFrom(page);
      _textCtrl.text = page.textContent;
    }
  }

  void _commit() {
    if (!mounted) return;
    final p = context.read<NotesProvider>();
    final pg = p.currentPage;
    if (pg == null || pg.id != _lastPageId) return;
    pg.strokes = List.from(_controller.strokes);
    pg.objects = List.from(_controller.objects);
    pg.updatedAt = DateTime.now();
    p.persist();
    p.refresh();
  }

  Future<String?> _textDialog(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 2,
          maxLines: 8,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text),
              child: const Text('Done')),
        ],
      ),
    );
    ctrl.dispose();
    return r;
  }

  Future<void> _createText(String type, Offset pos) async {
    final p = context.read<NotesProvider>();
    final t = await _textDialog(type == 'text' ? 'Add text' : 'New sticky note', '');
    if (t == null || t.trim().isEmpty || !mounted) return;
    final txt = t.trim();
    PageObject o;
    if (type == 'text') {
      const w = 420.0;
      o = PageObject(
        id: newId(),
        type: 'text',
        x: pos.dx,
        y: pos.dy,
        w: w,
        h: measureTextHeight(txt, p.textSize, w) + 8,
        text: txt,
        color: p.penColor.value,
        fontSize: p.textSize,
      );
    } else {
      o = PageObject(
        id: newId(),
        type: 'sticky',
        x: pos.dx - 120,
        y: pos.dy - 100,
        w: 240,
        h: 200,
        text: txt,
        color: p.stickyColor.value,
        fontSize: 22,
      );
    }
    _controller.addObject(o);
    _controller.selectOnly(object: o);
    _commit();
  }

  Future<void> _editObject(PageObject o) async {
    final t = await _textDialog('Edit', o.text);
    if (t == null || t.trim().isEmpty || !mounted) return;
    final txt = t.trim();
    final n = o.type == 'text'
        ? o.copyWith(text: txt, h: measureTextHeight(txt, o.fontSize, o.w) + 8)
        : o.copyWith(text: txt);
    _controller.updateObject(n);
    _controller.selectOnly(object: n);
    _commit();
  }

  Offset _viewCenter() =>
      _canvasKey.currentState?.viewCenter() ?? const Offset(kPageW / 2, 300);

  Future<void> _addImages() async {
    final p = context.read<NotesProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.image, allowMultiple: true);
      if (res == null) return;
      var center = _viewCenter();
      PageObject? last;
      for (final f in res.files) {
        if (f.path == null) continue;
        final ext = (f.extension ?? 'png').toLowerCase();
        final dest = File(
            '${p.mediaDir.path}${Platform.pathSeparator}img_${newId()}.$ext');
        await File(f.path!).copy(dest.path);
        final codec = await ui.instantiateImageCodec(await dest.readAsBytes());
        final frame = await codec.getNextFrame();
        final iw = frame.image.width.toDouble();
        final ih = frame.image.height.toDouble();
        frame.image.dispose();
        final pg = p.currentPage;
        final maxW = (pg != null && pg.isBoard) ? 700.0 : 500.0;
        final w = iw > maxW ? maxW : (iw < 120 ? 120.0 : iw);
        final h = w * ih / iw;
        last = PageObject(
          id: newId(),
          type: 'image',
          x: center.dx - w / 2,
          y: center.dy - h / 2,
          w: w,
          h: h,
          path: dest.path,
        );
        _controller.addObject(last);
        center = center + const Offset(40, 40);
      }
      if (last != null) {
        p.update(() => p.tool = ToolType.select);
        _controller.selectOnly(object: last);
        _commit();
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not add photo: $e')));
    }
  }

  void _addSticker(String emoji) {
    final c = _viewCenter();
    final o = PageObject(
      id: newId(),
      type: 'sticker',
      x: c.dx - 55,
      y: c.dy - 55,
      w: 110,
      h: 110,
      text: emoji,
    );
    _controller.addObject(o);
    final p = context.read<NotesProvider>();
    p.update(() => p.tool = ToolType.select);
    _controller.selectOnly(object: o);
    _commit();
  }

  void _stickerSheet() {
    showModalBottomSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final e in kStickers)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(sheet);
                    _addSticker(e);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(e, style: const TextStyle(fontSize: 34)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _insertTextBox(String text) {
    final p = context.read<NotesProvider>();
    final pg = p.currentPage;
    if (pg == null) return;
    final c = _viewCenter();
    final w = pg.isBoard ? 700.0 : pg.w - 160;
    final x = pg.isBoard ? c.dx - w / 2 : 80.0;
    double y = pg.isBoard ? c.dy - 100 : 80.0;
    if (!pg.isBoard) {
      for (final o in _controller.objects) {
        y = math.max(y, o.rect.bottom + 24);
      }
    }
    final o = PageObject(
      id: newId(),
      type: 'text',
      x: x,
      y: y,
      w: w,
      h: measureTextHeight(text, 24, w) + 8,
      text: text,
      color: 0xFF1F2937,
      fontSize: 24,
    );
    _controller.addObject(o);
    _commit();
  }

  Future<Uint8List> _pagePng() async {
    _commit();
    final pg = context.read<NotesProvider>().currentPage!;
    final r = await renderPage(pg, scale: 1.3);
    return r.bytes;
  }

  // ── export ──
  Future<void> _export(NotesProvider p, String what) async {
    final messenger = ScaffoldMessenger.of(context);
    _commit();
    final nb = p.currentNotebook;
    final cur = p.currentPage;
    if (nb == null || cur == null) return;
    try {
      messenger.showSnackBar(const SnackBar(content: Text('Preparing…')));
      if (what == 'png') {
        final r = await renderPage(cur, scale: 2);
        final ok = await saveBytesAs('${nb.name} - ${cur.title}.png', r.bytes);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text(ok ? 'Saved' : 'Cancelled')));
        return;
      }
      final pages = what == 'pdf_all' || what == 'print_all'
          ? List<NotePage>.from(nb.pages)
          : [cur];
      final bytes = await buildPdf(pages);
      messenger.hideCurrentSnackBar();
      if (what.startsWith('print')) {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${nb.name}.pdf');
      } else {
        final ok = await saveBytesAs('${nb.name}.pdf', bytes);
        messenger.showSnackBar(SnackBar(content: Text(ok ? 'Saved' : 'Cancelled')));
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  void _menu(NotesProvider p, String v) {
    if (v.startsWith('bg:')) {
      p.setBackground(v.substring(3));
    } else if (v.startsWith('paper:')) {
      p.setPaper(int.parse(v.substring(6), radix: 16));
    } else {
      switch (v) {
        case 'fit':
          _canvasKey.currentState?.fit();
          break;
        case 'present':
          _prevTool = p.tool;
          p.update(() => p.tool = ToolType.laser);
          setState(() => _presenting = true);
          break;
        case 'text':
          setState(() => _textMode = !_textMode);
          break;
        default:
          _export(p, v);
      }
    }
  }

  void _goToPage(NotesProvider p, String id, {bool closeDrawer = false}) {
    _commit();
    p.selectPage(id);
    if (closeDrawer) Navigator.pop(context);
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    final p = context.watch<NotesProvider>();
    final page = p.currentPage;
    if (page == null) {
      return const Scaffold(body: Center(child: Text('No page selected')));
    }
    _loadPageIfNeeded(page);
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      key: _scaffoldKey,
      drawer: !isWide ? Drawer(child: _pagesPanel(p, true)) : null,
      endDrawer: !isWide ? Drawer(width: 360, child: _aiPanel(p)) : null,
      body: Column(
        children: [
          if (!_presenting) _topBar(p, page),
          Expanded(
            child: Row(
              children: [
                if (isWide && _showPages && !_presenting)
                  SizedBox(width: 230, child: _pagesPanel(p, false)),
                Expanded(child: _canvasArea(p, page)),
                if (isWide && _showAi && !_presenting)
                  SizedBox(width: 340, child: _aiPanel(p)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiPanel(NotesProvider p) => AiPanel(
        provider: p,
        getPagePng: _pagePng,
        onInsert: _insertTextBox,
        onSaveText: (t) {
          p.setPageText(t);
          _textCtrl.text = t;
        },
      );

  Widget _topBar(NotesProvider p, NotePage page) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    Widget ib(IconData i, String tip, VoidCallback? f) => IconButton(
          icon: Icon(i),
          color: Colors.white,
          disabledColor: Colors.white38,
          tooltip: tip,
          onPressed: f,
        );
    return Container(
      color: kBar,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ib(Icons.arrow_back, 'Back', () {
                  _commit();
                  p.flush();
                  Navigator.pop(context);
                }),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _renameTitle(p, page),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(page.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        Text(p.currentNotebook?.name ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, __) => Row(children: [
                    ib(
                        Icons.undo,
                        'Undo',
                        _controller.canUndo
                            ? () {
                                _controller.undo();
                                _commit();
                              }
                            : null),
                    ib(
                        Icons.redo,
                        'Redo',
                        _controller.canRedo
                            ? () {
                                _controller.redo();
                                _commit();
                              }
                            : null),
                  ]),
                ),
                ib(Icons.view_carousel_outlined, 'Pages', () {
                  if (isWide) {
                    setState(() => _showPages = !_showPages);
                  } else {
                    _scaffoldKey.currentState?.openDrawer();
                  }
                }),
                ib(Icons.auto_awesome, 'AI', () {
                  if (isWide) {
                    setState(() => _showAi = !_showAi);
                  } else {
                    _scaffoldKey.currentState?.openEndDrawer();
                  }
                }),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (v) => _menu(p, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'bg:blank', child: Text('Background: Blank')),
                    PopupMenuItem(value: 'bg:lined', child: Text('Background: Lined')),
                    PopupMenuItem(value: 'bg:grid', child: Text('Background: Grid')),
                    PopupMenuItem(value: 'bg:dotted', child: Text('Background: Dotted')),
                    PopupMenuItem(value: 'bg:cornell', child: Text('Background: Cornell')),
                    PopupMenuItem(
                        value: 'bg:music', child: Text('Background: Music staff')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'paper:FFFFFFFF', child: Text('Paper: White')),
                    PopupMenuItem(value: 'paper:FFFFF8E1', child: Text('Paper: Cream')),
                    PopupMenuItem(value: 'paper:FFF1F3F4', child: Text('Paper: Gray')),
                    PopupMenuItem(value: 'paper:FF1E1E1E', child: Text('Paper: Dark')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'fit', child: Text('Fit to screen')),
                    PopupMenuItem(value: 'present', child: Text('Present (laser)')),
                    PopupMenuItem(value: 'text', child: Text('Typed notes')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'pdf_page', child: Text('Save page as PDF')),
                    PopupMenuItem(value: 'pdf_all', child: Text('Save notebook as PDF')),
                    PopupMenuItem(value: 'png', child: Text('Save page as image')),
                    PopupMenuItem(value: 'print_all', child: Text('Print / share PDF')),
                  ],
                ),
              ],
            ),
            _toolRow(p),
          ],
        ),
      ),
    );
  }

  Widget _toolRow(NotesProvider p) {
    Widget tool(IconData i, String tip, ToolType t) {
      final sel = p.tool == t;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => p.update(() => p.tool = t),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: sel ? Colors.white24 : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(i, color: Colors.white, size: 22),
            ),
          ),
        ),
      );
    }

    Widget action(IconData i, String tip, VoidCallback f) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Tooltip(
            message: tip,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: f,
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Icon(i, color: Colors.white, size: 22),
              ),
            ),
          ),
        );

    return LayoutBuilder(
      builder: (ctx, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              tool(Icons.highlight_alt, 'Select / lasso', ToolType.select),
              tool(Icons.edit, 'Pen', ToolType.pen),
              tool(Icons.border_color, 'Highlighter', ToolType.highlighter),
              tool(Icons.auto_fix_normal, 'Eraser', ToolType.eraser),
              tool(Icons.text_fields, 'Text', ToolType.text),
              tool(Icons.category_outlined, 'Shapes', ToolType.shape),
              tool(Icons.sticky_note_2_outlined, 'Sticky note', ToolType.sticky),
              tool(Icons.radio_button_checked, 'Laser pointer', ToolType.laser),
              Container(
                  width: 1,
                  height: 24,
                  color: Colors.white30,
                  margin: const EdgeInsets.symmetric(horizontal: 6)),
              action(Icons.add_photo_alternate_outlined, 'Add photo', _addImages),
              action(Icons.emoji_emotions_outlined, 'Stickers', _stickerSheet),
            ],
          ),
        ),
      ),
    );
  }

  Widget _canvasArea(NotesProvider p, NotePage page) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? const Color(0xFF16161A) : const Color(0xFFDFE1E8),
      child: Stack(
        children: [
          Positioned.fill(
            child: _textMode
                ? Padding(padding: const EdgeInsets.all(12), child: _textEditor(p))
                : CanvasView(
                    key: _canvasKey,
                    controller: _controller,
                    page: page,
                    provider: p,
                    onCreateText: _createText,
                    onEditObject: _editObject,
                    onChanged: _commit,
                  ),
          ),
          if (!_presenting && !_textMode)
            Positioned(
              top: 10,
              left: 8,
              right: 8,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: _optionsPill(p),
                ),
              ),
            ),
          if (!_presenting && !_textMode)
            Positioned(
                bottom: 12, left: 0, right: 0, child: Center(child: _pageNav(p))),
          if (_presenting)
            Positioned(
              top: 12,
              right: 12,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.black87),
                icon: const Icon(Icons.close),
                label: const Text('Exit'),
                onPressed: () {
                  p.update(() => p.tool = _prevTool);
                  setState(() => _presenting = false);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill(List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _colorDot(Color c, bool sel, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(
              color: sel ? kBrand : Colors.grey.shade400,
              width: sel ? 3 : 1,
            ),
          ),
        ),
      );

  Widget _widthBtn(double w, bool sel, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? kBrand.withOpacity(0.16) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Container(
            width: 22,
            height: math.max(2.0, math.min(w / 1.6, 14.0)),
            decoration: BoxDecoration(
              color: sel ? kBrand : Colors.grey.shade600,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );

  Widget _chip(String label, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: sel,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onTap(),
        ),
      );

  Widget _divider() => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: Colors.grey.shade400,
      );

  Widget _optionsPill(NotesProvider p) {
    switch (p.tool) {
      case ToolType.pen:
        return _pill([
          for (final k in const ['pen', 'ballpoint', 'pencil', 'brush', 'marker'])
            _chip(k[0].toUpperCase() + k.substring(1), p.penKind == k,
                () => p.update(() => p.penKind = k)),
          _divider(),
          for (final w in const [2.0, 4.0, 7.0, 12.0])
            _widthBtn(w, p.penWidth == w, () => p.update(() => p.penWidth = w)),
          _divider(),
          for (final c in kPenColors)
            _colorDot(c, p.penColor.value == c.value,
                () => p.update(() => p.penColor = c)),
          _divider(),
          _chip('Auto shapes', p.autoShape,
              () => p.update(() => p.autoShape = !p.autoShape)),
        ]);
      case ToolType.highlighter:
        return _pill([
          for (final w in const [16.0, 24.0, 36.0])
            _widthBtn(w / 2, p.highlightWidth == w,
                () => p.update(() => p.highlightWidth = w)),
          _divider(),
          for (final c in kHighlightColors)
            _colorDot(c, p.highlightColor.value == c.value,
                () => p.update(() => p.highlightColor = c)),
        ]);
      case ToolType.eraser:
        return _pill([
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('Touch a stroke to erase it'),
          ),
          TextButton(
            onPressed: () {
              _controller.clearInk();
              _commit();
            },
            child: const Text('Clear all ink'),
          ),
        ]);
      case ToolType.shape:
        const shapes = {
          'line': Icons.horizontal_rule,
          'arrow': Icons.arrow_right_alt,
          'rect': Icons.crop_square,
          'ellipse': Icons.circle_outlined,
          'triangle': Icons.change_history,
          'diamond': Icons.diamond_outlined,
        };
        return _pill([
          for (final e in shapes.entries)
            IconButton(
              icon: Icon(e.value),
              color: p.shapeType == e.key ? kBrand : null,
              onPressed: () => p.update(() => p.shapeType = e.key),
            ),
          _divider(),
          for (final w in const [2.0, 4.0, 7.0])
            _widthBtn(w, p.penWidth == w, () => p.update(() => p.penWidth = w)),
          _divider(),
          for (final c in kPenColors.take(9))
            _colorDot(c, p.penColor.value == c.value,
                () => p.update(() => p.penColor = c)),
        ]);
      case ToolType.text:
        return _pill([
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('Tap the page to type'),
          ),
          for (final s in const [20.0, 28.0, 40.0, 56.0])
            _chip('${s.toInt()}', p.textSize == s, () => p.update(() => p.textSize = s)),
          _divider(),
          for (final c in kPenColors.take(9))
            _colorDot(c, p.penColor.value == c.value,
                () => p.update(() => p.penColor = c)),
        ]);
      case ToolType.sticky:
        return _pill([
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('Tap the page for a note'),
          ),
          for (final c in kStickyColors)
            _colorDot(c, p.stickyColor.value == c.value,
                () => p.update(() => p.stickyColor = c)),
        ]);
      case ToolType.select:
        return AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => _pill([
            if (_controller.hasSelection) ...[
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Duplicate'),
                onPressed: () {
                  _controller.duplicateSelection();
                  _commit();
                },
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
                onPressed: () {
                  _controller.deleteSelection();
                  _commit();
                },
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Tap an item, or draw a loop around ink to select'),
              ),
          ]),
        );
      case ToolType.laser:
        return _pill([
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('Laser pointer: drag to point'),
          ),
        ]);
    }
  }

  Widget _pageNav(NotesProvider p) {
    final nb = p.currentNotebook;
    if (nb == null) return const SizedBox();
    final idx = nb.pages.indexWhere((x) => x.id == p.currentPageId);
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left),
            onPressed: idx > 0 ? () => _goToPage(p, nb.pages[idx - 1].id) : null,
          ),
          Text('${idx + 1} / ${nb.pages.length}'),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right),
            onPressed: idx >= 0 && idx < nb.pages.length - 1
                ? () => _goToPage(p, nb.pages[idx + 1].id)
                : null,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'New page',
            onPressed: () {
              _commit();
              p.addPage();
            },
          ),
        ],
      ),
    );
  }

  Widget _textEditor(NotesProvider p) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Expanded(
                child: Text('Typed notes (used by AI and search)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () => setState(() => _textMode = false),
                child: const Text('Back to page'),
              ),
            ],
          ),
        ),
        Expanded(
          child: TextField(
            controller: _textCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              hintText: 'Type your notes here…',
            ),
            onChanged: (v) => p.setPageText(v),
          ),
        ),
      ],
    );
  }

  Widget _pagesPanel(NotesProvider p, bool drawer) {
    final nb = p.currentNotebook;
    if (nb == null) return const SizedBox();
    return Material(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(nb.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'New page',
                    onPressed: () {
                      _commit();
                      p.addPage();
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: nb.pages.length,
                itemBuilder: (ctx, i) {
                  final pg = nb.pages[i];
                  final selected = pg.id == p.currentPageId;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: selected ? kBrand : Colors.transparent, width: 2),
                      color: selected ? kBrand.withOpacity(0.08) : null,
                    ),
                    child: InkWell(
                      onTap: () => _goToPage(p, pg.id, closeDrawer: drawer),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('${i + 1}. ${pg.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                iconSize: 18,
                                onSelected: (v) {
                                  _commit();
                                  if (v == 'dup') p.duplicatePage(pg.id);
                                  if (v == 'up') p.movePage(pg.id, -1);
                                  if (v == 'down') p.movePage(pg.id, 1);
                                  if (v == 'del') p.deletePage(pg.id);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'dup', child: Text('Duplicate')),
                                  PopupMenuItem(value: 'up', child: Text('Move up')),
                                  PopupMenuItem(value: 'down', child: Text('Move down')),
                                  PopupMenuItem(value: 'del', child: Text('Delete')),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(
                            height: 150,
                            child: Center(child: PageThumb(page: pg)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameTitle(NotesProvider p, NotePage page) async {
    final ctrl = TextEditingController(text: page.title);
    final r = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Rename page'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (r != null && r.isNotEmpty) p.renamePage(page.id, r);
  }
}
