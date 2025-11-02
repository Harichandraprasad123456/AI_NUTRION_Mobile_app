import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LogMealService {
  final Dio _dio = Dio();
  static const String _baseUrl = 'https://api.logmeal.es/v2';

  Future<List<DetectedFood>> detectFood(String imagePath) async {
    try {
      // Get API key from .env
      final apiKey = dotenv.env['LOGMEAL_API_KEY'];
      if (apiKey == null) throw Exception('LogMeal API key not found in .env');

      // Prepare the image file
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(imagePath),
      });

      // Make API call
      final response = await _dio.post(
        '$_baseUrl/recognition/dish',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
      );

      if (response.statusCode == 200) {
        final List<dynamic> foodList = response.data['recognition_results'];
        return foodList.map((food) => DetectedFood(
          name: food['name'],
          confidence: food['probability'],
        )).toList();
      } else {
        throw Exception('Failed to detect food: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error detecting food: $e');
    }
  }
}

class DetectedFood {
  final String name;
  final double confidence;

  DetectedFood({
    required this.name,
    required this.confidence,
  });
}