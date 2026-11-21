import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';

/// CAP-02: sends a bill photo to the `parse-bill` Edge Function, which calls
/// Claude Haiku. The API key lives on the server, never in the app.
class BillParser {
  final SupabaseClient client;
  BillParser(this.client);

  Future<ParsedBill> parse(File image) async {
    final bytes = await image.readAsBytes();
    final ext = image.path.toLowerCase();
    final mediaType = ext.endsWith('.png') ? 'image/png' : (ext.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
    final res = await client.functions.invoke('parse-bill', body: {
      'image': base64Encode(bytes),
      'media_type': mediaType,
      'categories': defaultCategories.map((c) => c.id).toList(),
    });
    if (res.status != 200) throw Exception('Could not read the bill (${res.status})');
    return parseBillJson(res.data as Map<String, dynamic>);
  }
}

ParsedBill parseBillJson(Map<String, dynamic> j) => ParsedBill(
      merchant: j['merchant'] as String?,
      total: (j['total'] as num?)?.toDouble(),
      lines: [
        for (final l in (j['items'] as List? ?? const []))
          ParsedLine(
            (l['name'] as String?)?.trim().isNotEmpty == true ? l['name'] as String : 'Item',
            (l['amount'] as num).toDouble(),
            l['category'] as String? ?? 'other',
            (l['confidence'] as num?)?.toDouble() ?? 0.5,
          )
      ],
    );
