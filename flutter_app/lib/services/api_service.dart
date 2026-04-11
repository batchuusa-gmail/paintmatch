import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/app_config.dart';
import '../models/room_analysis.dart';
import '../models/paint_color.dart';

class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  final String _base = AppConfig.apiBaseUrl;

  // -------------------------------------------------------------------------
  // POST /analyze-room
  // -------------------------------------------------------------------------
  Future<RoomAnalysis> analyzeRoom(File imageFile) async {
    final uri = Uri.parse('$_base/analyze-room');
    final request = http.MultipartRequest('POST', uri);

    // Always send as JPEG — reads raw bytes and forces image/jpeg content type
    // This handles HEIC, HEIF, and other macOS-native formats
    final bytes = await imageFile.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes(
      'image',
      bytes,
      filename: 'room.jpg',
      contentType: MediaType.parse('image/jpeg'),
    ));

    print('[API] Sending ${bytes.length} bytes to $_base/analyze-room');

    final streamed = await request.send();
    final body = await http.Response.fromStream(streamed);

    print('[API] Response status: ${body.statusCode}');
    print('[API] Response body: ${body.body}');

    if (body.statusCode != 200) {
      throw Exception('Server error ${body.statusCode}: ${body.body}');
    }

    final json = jsonDecode(body.body) as Map<String, dynamic>;
    if (json['error'] != null) throw Exception(json['error']);
    return RoomAnalysis.fromJson(json['data'] as Map<String, dynamic>);
  }

  // -------------------------------------------------------------------------
  // POST /render-room
  // -------------------------------------------------------------------------
  Future<Map<String, String>> renderRoom({
    required String imageBase64,
    required String wallMaskBase64,
    required String targetHex,
    required String finish,
  }) async {
    final uri = Uri.parse('$_base/render-room');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'image': imageBase64,
        'wall_mask': wallMaskBase64,
        'target_hex': targetHex,
        'finish': finish,
      }),
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] != null) throw Exception(json['error']);
    final data = json['data'] as Map<String, dynamic>;
    return {
      'rendered_image_url': data['rendered_image_url'] as String,
      'target_hex': data['target_hex'] as String,
      'finish': data['finish'] as String,
    };
  }

  // -------------------------------------------------------------------------
  // POST /segment-wall
  // Returns base64 PNG mask — white = target surface, black = everything else
  // surface: "wall" | "ceiling" | "floor"
  // -------------------------------------------------------------------------
  Future<String> segmentWall({
    required String imageBase64,
    String surface = 'wall',
    double? seedX,
    double? seedY,
  }) async {
    final uri = Uri.parse('$_base/segment-wall');
    final body = <String, dynamic>{'image': imageBase64, 'surface': surface};
    if (seedX != null && seedY != null) {
      body['seed_x'] = seedX;
      body['seed_y'] = seedY;
    }
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] != null) throw Exception(json['error']);
    return (json['data'] as Map<String, dynamic>)['mask'] as String;
  }

  // -------------------------------------------------------------------------
  // GET /colors — all colors, optional vendor/search filter
  // -------------------------------------------------------------------------
  Future<List<PaintColor>> listColors({
    String? vendor,
    String? search,
    int limit = 200,
    int offset = 0,
  }) async {
    final params = <String, String>{'limit': '$limit', 'offset': '$offset'};
    if (vendor != null && vendor != 'all') params['vendor'] = vendor;
    if (search != null && search.isNotEmpty) params['search'] = search;
    final uri = Uri.parse('$_base/colors').replace(queryParameters: params);
    final response = await http.get(uri);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] != null) throw Exception(json['error']);
    final list = json['data'] as List<dynamic>;
    return list.map((e) => PaintColor.fromJson(e as Map<String, dynamic>)).toList();
  }

  // -------------------------------------------------------------------------
  // POST /match-colors
  // -------------------------------------------------------------------------
  Future<List<PaintColor>> matchColors(String hex, {int topN = 3}) async {
    final uri = Uri.parse('$_base/match-colors');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'hex': hex, 'top_n': topN}),
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] != null) throw Exception(json['error']);
    final list = json['data'] as List<dynamic>;
    return list
        .map((e) => PaintColor.fromJson(e as Map<String, dynamic>))
        .toList();
  }

}
