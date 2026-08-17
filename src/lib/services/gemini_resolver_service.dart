import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiResolveResult {
  final String? canonicalQuery;
  final List<String> alternatives;
  final String? category;
  final double? confidence;
  final double? densityKgPerLiter;
  final String? source;
  final bool trusted;

  const GeminiResolveResult({
    this.canonicalQuery,
    this.alternatives = const [],
    this.category,
    this.confidence,
    this.densityKgPerLiter,
    this.source,
    this.trusted = false,
  });

  factory GeminiResolveResult.fromJson(Map<String, dynamic> json) {
    return GeminiResolveResult(
      canonicalQuery: json['canonical_query']?.toString(),
      alternatives: (json['alternatives'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      category: json['category']?.toString(),
      confidence: (json['confidence'] is num)
          ? (json['confidence'] as num).toDouble()
          : double.tryParse(json['confidence']?.toString() ?? ''),
      densityKgPerLiter: (json['density_kg_per_liter'] is num)
          ? (json['density_kg_per_liter'] as num).toDouble()
          : double.tryParse(json['density_kg_per_liter']?.toString() ?? ''),
      source: json['source']?.toString(),
      trusted: json['trusted'] == true,
    );
  }
}

class GeminiResolverService {
  GeminiResolverService();

  final String endpointUrl =
      'https://resolveproductname-n6toulrcha-uc.a.run.app';

  Future<GeminiResolveResult?> resolveProductName({
    required String productName,
    String? productType,
  }) async {
    final uri = Uri.parse(endpointUrl);

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'productName': productName,
        'productType': productType ?? '',
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Gemini resolve failed: ${response.statusCode} ${response.body}',
      );
    }

    final parsed = jsonDecode(response.body) as Map<String, dynamic>;
    return GeminiResolveResult.fromJson(parsed);
  }
}
