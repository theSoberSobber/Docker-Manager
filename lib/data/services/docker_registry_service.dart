import 'dart:convert';
import 'package:http/http.dart' as http;

class DockerRegistryService {
  static const String defaultRegistry = 'https://hub.docker.com';

  /// Search for images in Docker Hub
  Future<List<ImageSearchResult>> searchImages(String query,
      {String registry = defaultRegistry}) async {
    try {
      final url = Uri.parse('$registry/v2/search/repositories/?page_size=25&query=$query');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        return results
            .map((item) => ImageSearchResult.fromJson(item))
            .toList();
      } else {
        throw Exception('Failed to search images: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching images: $e');
    }
  }

  /// Get available tags for an image
  Future<List<String>> getImageTags(String imageName,
      {String registry = defaultRegistry}) async {
    try {
      // Handle official images (library/)
      final repoName = imageName.contains('/') ? imageName : 'library/$imageName';
      
      final url = Uri.parse('$registry/v2/repositories/$repoName/tags?page_size=25');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        return results.map((item) => item['name'] as String).toList();
      } else {
        throw Exception('Failed to get tags: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error getting tags: $e');
    }
  }
}

class ImageSearchResult {
  final String name;
  final String description;
  final int starCount;
  final bool isOfficial;
  final bool isAutomated;

  ImageSearchResult({
    required this.name,
    required this.description,
    required this.starCount,
    required this.isOfficial,
    required this.isAutomated,
  });

  factory ImageSearchResult.fromJson(Map<String, dynamic> json) {
    return ImageSearchResult(
      name: json['repo_name'] ?? json['name'] ?? '',
      description: json['short_description'] ?? json['description'] ?? '',
      starCount: json['star_count'] ?? 0,
      isOfficial: json['is_official'] ?? false,
      isAutomated: json['is_automated'] ?? false,
    );
  }
}
