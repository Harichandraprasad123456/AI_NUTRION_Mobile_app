import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EdamamService {
  final Dio _dio = Dio();
  static const String _baseUrl = 'https://api.edamam.com/api/food-database/v2';

  Future<NutritionInfo> getNutrition(String foodName) async {
    try {
      // Get API credentials from .env
      final appId = dotenv.env['EDAMAM_APP_ID'];
      final appKey = dotenv.env['EDAMAM_APP_KEY'];
      
      if (appId == null || appKey == null) {
        throw Exception('Edamam API credentials not found in .env');
      }

      // Make API call
      final response = await _dio.get(
        '$_baseUrl/parser',
        queryParameters: {
          'app_id': appId,
          'app_key': appKey,
          'ingr': foodName,
        },
      );

      if (response.statusCode == 200 && response.data['hints'].length > 0) {
        final foodData = response.data['hints'][0]['food'];
        final nutrients = foodData['nutrients'];
        
        return NutritionInfo(
          name: foodData['label'],
          calories: nutrients['ENERC_KCAL']?.toDouble() ?? 0.0,
          protein: nutrients['PROCNT']?.toDouble() ?? 0.0,
          fat: nutrients['FAT']?.toDouble() ?? 0.0,
          carbs: nutrients['CHOCDF']?.toDouble() ?? 0.0,
          fiber: nutrients['FIBTG']?.toDouble() ?? 0.0,
        );
      } else {
        throw Exception('No nutrition data found for $foodName');
      }
    } catch (e) {
      throw Exception('Error getting nutrition info: $e');
    }
  }
}

class NutritionInfo {
  final String name;
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double fiber;

  NutritionInfo({
    required this.name,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.fiber,
  });

  Map<String, String> toDisplayMap() {
    return {
      'Calories': '${calories.toStringAsFixed(1)} kcal',
      'Protein': '${protein.toStringAsFixed(1)}g',
      'Fat': '${fat.toStringAsFixed(1)}g',
      'Carbs': '${carbs.toStringAsFixed(1)}g',
      'Fiber': '${fiber.toStringAsFixed(1)}g',
    };
  }
}