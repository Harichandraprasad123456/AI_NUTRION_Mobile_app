import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_package;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

// --- Global Variables ---
String edamamAppId = '';
String edamamAppKey = '';
String logmealApiToken = '';
String ollamaBaseUrl = 'http://127.0.0.1:11434';

// --- User Profile Data Class ---
class UserProfile {
  final String name;
  final String goal;
  final List<String> healthConditions;
  final List<String> dietaryPreferences;

  UserProfile({
    this.name = 'User',
    this.goal = 'Maintain health',
    this.healthConditions = const [],
    this.dietaryPreferences = const [],
  });
}

// --- Database Helper ---
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('nutrition.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = path_package.join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE meals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        calories REAL NOT NULL,
        protein REAL NOT NULL,
        fat REAL NOT NULL,
        carbs REAL NOT NULL,
        date TEXT NOT NULL,
        meal_type TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertMeal(Map<String, dynamic> meal) async {
    final db = await database;
    return await db.insert('meals', meal);
  }

  Future<List<Map<String, dynamic>>> getMealsByDate(String date) async {
    final db = await database;
    return await db.query('meals', where: 'date = ?', whereArgs: [date]);
  }

  Future<List<Map<String, dynamic>>> getRecentMeals(int days) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days));
    final dateStr = DateFormat('yyyy-MM-dd').format(startDate);

    return await db.query(
      'meals',
      where: 'date >= ?',
      whereArgs: [dateStr],
      orderBy: 'date DESC, id DESC',
    );
  }

  Future<Map<String, double>> getDailyTotals(String date) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        SUM(calories) as totalCalories,
        SUM(protein) as totalProtein,
        SUM(fat) as totalFat,
        SUM(carbs) as totalCarbs
      FROM meals
      WHERE date = ?
    ''', [date]);

    if (result.isNotEmpty && result.first['totalCalories'] != null) {
      return {
        'calories': (result.first['totalCalories'] as num).toDouble(),
        'protein': (result.first['totalProtein'] as num).toDouble(),
        'fat': (result.first['totalFat'] as num).toDouble(),
        'carbs': (result.first['totalCarbs'] as num).toDouble(),
      };
    }
    return {'calories': 0, 'protein': 0, 'fat': 0, 'carbs': 0};
  }

  Future<int> deleteMeal(int id) async {
    final db = await database;
    return await db.delete('meals', where: 'id = ?', whereArgs: [id]);
  }
}

// --- Entry Point ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final savedIp = prefs.getString('ollamaIp');
  if (savedIp != null && savedIp.isNotEmpty) {
    ollamaBaseUrl = 'http://$savedIp:11434';
    print('Loaded saved Ollama IP: $ollamaBaseUrl');
  }

  try {
    await dotenv.load(fileName: ".env");
    edamamAppId = dotenv.env['EDAMAM_APP_ID'] ?? '';
    edamamAppKey = dotenv.env['EDAMAM_APP_KEY'] ?? '';
    logmealApiToken = dotenv.env['LOGMEAL_API_TOKEN'] ?? '';

    if (edamamAppId.isEmpty ||
        edamamAppKey.isEmpty ||
        logmealApiToken.isEmpty) {
      print('ERROR: Scan API keys not found or missing in .env file.');
      print('NOTE: LogMeal 401 error means invalid/missing API token.');
    } else {
      print('Scan API keys loaded successfully.');
    }
  } catch (e) {
    print('ERROR loading .env file: $e');
  }

  runApp(const NutritionApp());
}

// --- Main App Widget ---
// --- Main App Widget ---
class NutritionApp extends StatelessWidget {
  const NutritionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Nutrition Coach',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFB),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Color(0xFF1A1A1A),
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: Color(0xFF00897B),
          unselectedItemColor: Color(0xFF9E9E9E),
          backgroundColor: Colors.white,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          selectedLabelStyle:
              TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: TextStyle(fontSize: 11),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
        ),
      ),
      home: const MainAppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Main Navigation Shell ---
class MainAppShell extends StatefulWidget {
  const MainAppShell({super.key});

  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> {
  int _selectedIndex = 0;

  static final List<Widget> _widgetOptions = <Widget>[
    const HomePage(),
    const ScanPage(),
    const HealthInsightsPage(),
    const ChatPage(),
    const ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _widgetOptions,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined, size: 26),
              activeIcon: Icon(Icons.home_rounded, size: 26),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt_outlined, size: 26),
              activeIcon: Icon(Icons.camera_alt_rounded, size: 26),
              label: 'Scan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.insights_rounded, size: 26),
              activeIcon: Icon(Icons.insights, size: 26),
              label: 'Insights',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline_rounded, size: 26),
              activeIcon: Icon(Icons.chat_bubble_rounded, size: 26),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded, size: 26),
              activeIcon: Icon(Icons.person_rounded, size: 26),
              label: 'Profile',
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

// Now your _HomePageState class follows

// --- Beautiful Home Page ---
class _HomePageState extends State<HomePage> {
  String userName = 'User';
  String userGoal = 'Maintain health';
  Map<String, double> todayTotals = {
    'calories': 0,
    'protein': 0,
    'fat': 0,
    'carbs': 0
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final totals = await DatabaseHelper.instance.getDailyTotals(today);

    if (mounted) {
      setState(() {
        userName = prefs.getString('name') ?? 'User';
        userGoal = prefs.getString('goal') ?? 'Maintain health';
        todayTotals = totals;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting = hour < 12
        ? 'Good Morning'
        : (hour < 17 ? 'Good Afternoon' : 'Good Evening');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(greeting,
                  style: TextStyle(fontSize: 18, color: Colors.grey[700])),
              const SizedBox(height: 8),
              Text(userName,
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 32),

              // Today's Progress Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF00897B), Color(0xFF4DB6AC)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Color(0xFF00897B).withOpacity(0.3),
                        blurRadius: 20,
                        offset: Offset(0, 10))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.today_rounded,
                            color: Colors.white, size: 28),
                        SizedBox(width: 12),
                        Text('Today\'s Nutrition',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildNutrientDisplay('Calories',
                            '${todayTotals['calories']?.round() ?? 0}', 'kcal'),
                        _buildNutrientDisplay(
                            'Protein',
                            '${todayTotals['protein']?.toStringAsFixed(1) ?? 0}',
                            'g'),
                        _buildNutrientDisplay(
                            'Carbs',
                            '${todayTotals['carbs']?.toStringAsFixed(1) ?? 0}',
                            'g'),
                        _buildNutrientDisplay(
                            'Fat',
                            '${todayTotals['fat']?.toStringAsFixed(1) ?? 0}',
                            'g'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Quick Actions
              const Text('Quick Actions',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildActionCard(
                      icon: Icons.camera_alt_rounded,
                      title: 'Scan Food',
                      color: const Color(0xFFFF6B6B),
                      onTap: () => context
                          .findAncestorStateOfType<_MainAppShellState>()
                          ?.setState(() => context
                              .findAncestorStateOfType<_MainAppShellState>()!
                              ._selectedIndex = 1),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildActionCard(
                      icon: Icons.history_rounded,
                      title: 'View History',
                      color: const Color(0xFF4ECDC4),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => MealHistoryPage())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Feature Cards (NOW FUNCTIONAL)
              InkWell(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (context) => AnalyticsPage())),
                child: _buildFeatureCard(
                  icon: Icons.analytics_rounded,
                  title: 'Progress Analytics',
                  description: 'Track your nutrition trends over time',
                  gradient: [const Color(0xFF667EEA), const Color(0xFF764BA2)],
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => HealthInsightsPage())),
                child: _buildFeatureCard(
                  icon: Icons.fitness_center_rounded,
                  title: 'Health Insights',
                  description: 'Get personalized recommendations',
                  gradient: [const Color(0xFFFFB75E), const Color(0xFFED8F03)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNutrientDisplay(String label, String value, String unit) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        Text(unit,
            style:
                TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
        const SizedBox(height: 4),
        Text(label,
            style:
                TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13)),
      ],
    );
  }

  Widget _buildActionCard(
      {required IconData icon,
      required String title,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2), width: 2),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Widget _buildFeatureCard({
  required IconData icon,
  required String title,
  required String description,
  required List<Color> gradient,
}) {
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// --- Beautiful Scan Page ---
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;
  bool _isProcessing = false;
  List<FoodResult> _results = [];
  String _errorMessage = '';

  Future<void> _takePicture() async {
    _resetState();
    try {
      final XFile? photo =
          await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo != null) {
        setState(() => _imageFile = photo);
        await _processImageOnline(photo.path);
      }
    } catch (e) {
      setState(() => _errorMessage = "Could not access camera.");
    }
  }

  Future<void> _saveMealToLog(FoodResult food) async {
    final mealType = await _showMealTypeDialog();
    if (mealType == null) return;

    // Parse nutrition values
    double calories =
        double.tryParse(food.calories.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    double protein = double.tryParse(
            food.protein?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ??
        0;
    double fat =
        double.tryParse(food.fat?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ??
            0;
    double carbs = double.tryParse(
            food.carbs?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ??
        0;

    final meal = {
      'name': food.name,
      'calories': calories,
      'protein': protein,
      'fat': fat,
      'carbs': carbs,
      'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'meal_type': mealType,
    };

    await DatabaseHelper.instance.insertMeal(meal);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text('${food.name} saved to $mealType!'),
            ],
          ),
          backgroundColor: const Color(0xFF4ECDC4),
        ),
      );
    }
  }

  Future<String?> _showMealTypeDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Meal Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Breakfast', 'Lunch', 'Dinner', 'Snack'].map((type) {
            return ListTile(
              title: Text(type),
              leading: Icon(_getMealIcon(type), color: const Color(0xFF00897B)),
              onTap: () => Navigator.pop(context, type),
            );
          }).toList(),
        ),
      ),
    );
  }

  IconData _getMealIcon(String mealType) {
    switch (mealType) {
      case 'Breakfast':
        return Icons.breakfast_dining_rounded;
      case 'Lunch':
        return Icons.lunch_dining_rounded;
      case 'Dinner':
        return Icons.dinner_dining_rounded;
      case 'Snack':
        return Icons.fastfood_rounded;
      default:
        return Icons.restaurant_rounded;
    }
  }

  Future<void> _pickFromGallery() async {
    _resetState();
    try {
      final XFile? image = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85);
      if (image != null) {
        setState(() => _imageFile = image);
        await _processImageOnline(image.path);
      }
    } catch (e) {
      setState(() => _errorMessage = "Could not access gallery.");
    }
  }

  void _resetState() {
    setState(() {
      _imageFile = null;
      _isProcessing = false;
      _results = [];
      _errorMessage = '';
    });
  }

  Future<Uint8List> _compressImage(String imagePath) async {
    try {
      File imageFile = File(imagePath);
      Uint8List imageBytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) throw Exception('Could not decode image');

      int maxDimension = 1024;
      int newWidth = originalImage.width;
      int newHeight = originalImage.height;

      if (originalImage.width > maxDimension ||
          originalImage.height > maxDimension) {
        if (originalImage.width > originalImage.height) {
          newWidth = maxDimension;
          newHeight =
              ((originalImage.height * maxDimension) / originalImage.width)
                  .round();
        } else {
          newHeight = maxDimension;
          newWidth =
              ((originalImage.width * maxDimension) / originalImage.height)
                  .round();
        }
        originalImage =
            img.copyResize(originalImage, width: newWidth, height: newHeight);
      }

      return Uint8List.fromList(img.encodeJpg(originalImage, quality: 85));
    } catch (e) {
      return await File(imagePath).readAsBytes();
    }
  }

  Future<void> _processImageOnline(String imagePath) async {
    if (logmealApiToken.isEmpty ||
        edamamAppId.isEmpty ||
        edamamAppKey.isEmpty) {
      setState(() {
        _errorMessage =
            '⚠️ API Keys not configured.\n\nLogMeal 401 error usually means:\n• Invalid API token in .env file\n• Expired API subscription\n• Missing LOGMEAL_API_TOKEN\n\nPlease check your .env file and restart the app.';
        _isProcessing = false;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = '';
      _results = [];
    });

    List<String> detectedFoodNames = [];
    String currentErrorMessage = '';

    try {
      Uint8List compressedImageBytes = await _compressImage(imagePath);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.logmeal.com/v2/recognition/dish'),
      );
      request.headers['Authorization'] = 'Bearer $logmealApiToken';
      request.files.add(http.MultipartFile.fromBytes(
          'image', compressedImageBytes,
          filename: 'image.jpg'));

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data.containsKey('recognition_results') &&
            data['recognition_results'] is List) {
          for (var item in data['recognition_results']) {
            if (item is Map && item.containsKey('name')) {
              detectedFoodNames.add(item['name']);
            }
          }
        }
        detectedFoodNames = detectedFoodNames.toSet().toList();
        if (detectedFoodNames.isEmpty) {
          currentErrorMessage =
              'No specific food items recognized in the image.';
        }
      } else if (response.statusCode == 401) {
        currentErrorMessage =
            '🔑 LogMeal API Authentication Failed (401)\n\nThis means:\n• Invalid API token\n• Expired subscription\n• Missing authorization\n\nPlease verify your LOGMEAL_API_TOKEN in the .env file.';
      } else {
        currentErrorMessage =
            'Error from LogMeal API (Status: ${response.statusCode})';
      }
    } on TimeoutException catch (_) {
      currentErrorMessage =
          'Request timed out. Please check your internet connection.';
    } catch (e) {
      currentErrorMessage =
          'Failed to connect to food recognition service.\n\nError: $e';
    }

    if (detectedFoodNames.isEmpty) {
      setState(() {
        _errorMessage = currentErrorMessage.isEmpty
            ? 'No food items recognized.'
            : currentErrorMessage;
        _isProcessing = false;
      });
      return;
    }
    detectedFoodNames = detectedFoodNames.take(5).toList();

    List<FoodResult> fetchedResults = [];

// Process items with delay to respect rate limits
    for (int i = 0; i < detectedFoodNames.length; i++) {
      String foodName = detectedFoodNames[i];

      if (foodName.toLowerCase() == 'food' || foodName.toLowerCase() == 'dish')
        continue;

      // Add 1 second delay between requests (10 per minute limit)
      if (i > 0) {
        await Future.delayed(const Duration(seconds: 1));
      }

      try {
        final searchUri =
            Uri.parse('https://api.edamam.com/api/food-database/v2/parser'
                '?app_id=$edamamAppId'
                '&app_key=$edamamAppKey'
                '&ingr=${Uri.encodeComponent(foodName)}'
                '&nutrition-type=cooking');

        print(
            '🔍 Fetching nutrition for: $foodName (${i + 1}/${detectedFoodNames.length})');

        final searchResponse =
            await http.get(searchUri).timeout(const Duration(seconds: 15));

        print('📊 API Response Status: ${searchResponse.statusCode}');

        if (searchResponse.statusCode == 200) {
          final searchData = json.decode(searchResponse.body);

          if (searchData['hints'] != null && searchData['hints'].isNotEmpty) {
            final firstFood = searchData['hints'][0]['food'];
            final nutrients = firstFood['nutrients'];

            String cals = nutrients['ENERC_KCAL'] != null
                ? '${nutrients['ENERC_KCAL'].round()} kcal'
                : 'N/A';

            String prot = nutrients['PROCNT'] != null
                ? '${nutrients['PROCNT'].toStringAsFixed(1)} g'
                : 'N/A';

            String fat = nutrients['FAT'] != null
                ? '${nutrients['FAT'].toStringAsFixed(1)} g'
                : 'N/A';

            double totalCarbs = nutrients['CHOCDF']?.toDouble() ?? 0.0;
            double fiber = nutrients['FIBTG']?.toDouble() ?? 0.0;
            double netCarbs = totalCarbs - fiber;
            if (netCarbs < 0) netCarbs = 0;

            String carbs =
                totalCarbs > 0 ? '${netCarbs.toStringAsFixed(1)} g' : 'N/A';

            fetchedResults.add(FoodResult(
              name: foodName,
              calories: cals,
              protein: prot,
              fat: fat,
              carbs: carbs,
            ));

            print('✅ Successfully fetched nutrition for: $foodName');

            // Update UI progressively as each item is fetched
            setState(() {
              _results = List.from(fetchedResults);
            });
          } else {
            fetchedResults.add(FoodResult(
              name: foodName,
              calories: 'N/A',
              details: 'Food not found in database',
            ));
            print('⚠️ No nutrition data found for: $foodName');

            setState(() {
              _results = List.from(fetchedResults);
            });
          }
        } else if (searchResponse.statusCode == 401) {
          fetchedResults.add(FoodResult(
            name: foodName,
            calories: 'N/A',
            details: 'Invalid API credentials',
          ));
          print('❌ 401 Error: Check your Edamam credentials');
          break; // Stop processing if credentials are invalid
        } else if (searchResponse.statusCode == 429) {
          fetchedResults.add(FoodResult(
            name: foodName,
            calories: 'N/A',
            details: 'Rate limit - wait 1 minute',
          ));
          print('⏱️ 429 Error: Rate limit. Please wait before scanning again.');
          break; // Stop processing to avoid more errors
        } else {
          fetchedResults.add(FoodResult(
            name: foodName,
            calories: 'N/A',
            details: 'API error: ${searchResponse.statusCode}',
          ));
          print('❌ API Error ${searchResponse.statusCode}');

          setState(() {
            _results = List.from(fetchedResults);
          });
        }
      } catch (e) {
        fetchedResults.add(FoodResult(
          name: foodName,
          calories: 'N/A',
          details: 'Connection error',
        ));
        print('❌ Exception for $foodName: $e');

        setState(() {
          _results = List.from(fetchedResults);
        });
      }
    }

// Final update
    setState(() {
      _results = fetchedResults;
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Food'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF00897B).withOpacity(0.05),
                Colors.transparent
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image Display
              Container(
                height: 280,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  image: _imageFile != null
                      ? DecorationImage(
                          image: FileImage(File(_imageFile!.path)),
                          fit: BoxFit.cover)
                      : null,
                ),
                child: _imageFile == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.image_search_rounded,
                                size: 80, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              'No image selected',
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: _buildScanButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      gradient: [
                        const Color(0xFFFF6B6B),
                        const Color(0xFFFF8E53)
                      ],
                      onPressed: _isProcessing ? null : _takePicture,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildScanButton(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      gradient: [
                        const Color(0xFF4ECDC4),
                        const Color(0xFF44A08D)
                      ],
                      onPressed: _isProcessing ? null : _pickFromGallery,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Processing Indicator
              if (_isProcessing)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(strokeWidth: 3),
                      const SizedBox(height: 16),
                      Text(
                        'Analyzing your food...',
                        style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

              // Error Message
              if (_errorMessage.isNotEmpty && !_isProcessing)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.shade200, width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Colors.red.shade700, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.red.shade900,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),

              // Results Display
              if (_results.isNotEmpty && !_isProcessing)
                ..._results.map((result) => _buildResultCard(result)).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanButton({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient:
                onPressed != null ? LinearGradient(colors: gradient) : null,
            color: onPressed == null ? Colors.grey.shade300 : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: onPressed != null
                ? [
                    BoxShadow(
                        color: gradient[0].withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6))
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(FoodResult result) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 15,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.restaurant_rounded,
                    color: Color(0xFF00897B), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(result.name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (result.calories != 'N/A' && result.calories != 'Error') ...[
            _buildNutritionItem(Icons.local_fire_department_rounded, 'Calories',
                result.calories, const Color(0xFFFF6B6B)),
            const SizedBox(height: 12),
            _buildNutritionItem(Icons.fitness_center_rounded, 'Protein',
                result.protein ?? 'N/A', const Color(0xFF4ECDC4)),
            const SizedBox(height: 12),
            _buildNutritionItem(Icons.water_drop_rounded, 'Fat',
                result.fat ?? 'N/A', const Color(0xFFFFB75E)),
            const SizedBox(height: 12),
            _buildNutritionItem(Icons.grain_rounded, 'Net Carbs',
                result.carbs ?? 'N/A', const Color(0xFF667EEA)),
            const SizedBox(height: 16),
            // ADD SAVE BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _saveMealToLog(result),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Save to Meal Log'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(result.details ?? 'Could not fetch details.',
                          style: TextStyle(
                              fontSize: 14, color: Colors.orange.shade900))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNutritionItem(
      IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700])),
        ),
        Text(value,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A))),
      ],
    );
  }
}

// --- Food Result Class ---
class FoodResult {
  final String name;
  final String calories;
  final String? protein;
  final String? fat;
  final String? carbs;
  final String? details;

  FoodResult(
      {required this.name,
      required this.calories,
      this.protein,
      this.fat,
      this.carbs,
      this.details});

  factory FoodResult.fromJson(String foodName, Map<String, dynamic> json) {
    String cals = 'N/A';
    String prot = 'N/A';
    String fatTotal = 'N/A';
    String carbsNet = 'N/A';

    try {
      final nutrients = json['totalNutrients'] as Map<String, dynamic>? ?? {};

      if (nutrients.containsKey('ENERC_KCAL')) {
        final qty = (nutrients['ENERC_KCAL']['quantity'] as num?)?.round();
        if (qty != null) cals = '$qty kcal';
      }

      if (nutrients.containsKey('PROCNT')) {
        final qty =
            (nutrients['PROCNT']['quantity'] as num?)?.toStringAsFixed(1);
        if (qty != null) prot = '$qty g';
      }

      if (nutrients.containsKey('FAT')) {
        final qty = (nutrients['FAT']['quantity'] as num?)?.toStringAsFixed(1);
        if (qty != null) fatTotal = '$qty g';
      }

      double totalCarbsQty = 0.0;
      if (nutrients.containsKey('CHOCDF')) {
        totalCarbsQty =
            (nutrients['CHOCDF']['quantity'] as num?)?.toDouble() ?? 0.0;
      }
      double fiberQty = 0.0;
      if (nutrients.containsKey('FIBTG')) {
        fiberQty = (nutrients['FIBTG']['quantity'] as num?)?.toDouble() ?? 0.0;
      }
      double netCarbsValue = totalCarbsQty - fiberQty;
      if (netCarbsValue < 0) netCarbsValue = 0;
      carbsNet = '${netCarbsValue.toStringAsFixed(1)} g';
    } catch (e) {
      cals = 'Error';
    }

    return FoodResult(
        name: foodName,
        calories: cals,
        protein: prot,
        fat: fatTotal,
        carbs: carbsNet);
  }
}

// --- Beautiful Chat Page ---
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  UserProfile _userProfile = UserProfile();
  final TextEditingController _ipController = TextEditingController();
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _ipController.text =
        ollamaBaseUrl.replaceAll('http://', '').replaceAll(':11434', '');
    _messages.add(ChatMessage(
      text: 'Hi! I\'m your AI Nutrition Coach powered by Gemma 2B 🤖\n\n'
          '📱 Setup Instructions:\n'
          '1️⃣ Ensure Ollama is running on your laptop\n'
          '2️⃣ Find your laptop\'s local IP address\n'
          '3️⃣ Enter it below and tap "Connect"\n'
          '4️⃣ Both devices must be on the same Wi-Fi\n\n'
          'Once connected, ask me anything about nutrition!',
      isUser: false,
    ));
  }

  Future<void> _loadUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('name') ?? 'User';
      final goal = prefs.getString('goal') ?? 'Maintain health';
      final conditions = prefs.getStringList('healthConditions') ?? [];
      final preferences = prefs.getStringList('dietaryPreferences') ?? [];

      if (mounted) {
        setState(() {
          _userProfile = UserProfile(
              name: name,
              goal: goal,
              healthConditions: conditions,
              dietaryPreferences: preferences);
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isLoading = true);

    try {
      final response = await http
          .get(Uri.parse('$ollamaBaseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          _isConnected = true;
          _isLoading = false;
        });
        _showSuccessDialog('Connected! 🎉',
            'Successfully connected to Ollama\n\nYou can now start chatting with your AI nutritionist!');
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isLoading = false;
      });
      _showErrorDialog(
          'Connection Failed ❌',
          'Could not connect to Ollama\n\n'
              'Please verify:\n'
              '✓ Ollama is running on your laptop\n'
              '✓ The IP address is correct\n'
              '✓ Same Wi-Fi network\n'
              '✓ Firewall allows port 11434');
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isLoading) return;

    if (!_isConnected) {
      _showErrorDialog('Not Connected', 'Please connect to Ollama first!');
      return;
    }

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });

    _messageController.clear();
    _scrollToBottom();
    _generateOllamaResponse(text);
  }

  Future<void> _generateOllamaResponse(String userMessage) async {
    const modelName = 'gemma2:2b';

    final systemPrompt =
        "You are a friendly, professional nutritionist specialized in Indian diets and health conditions. "
        "You're advising ${_userProfile.name}. Answer concisely and helpfully.\n\n"
        "User Profile:\n"
        "• Goal: ${_userProfile.goal}\n"
        "• Conditions: ${_userProfile.healthConditions.isEmpty ? 'None' : _userProfile.healthConditions.join(', ')}\n"
        "• Preferences: ${_userProfile.dietaryPreferences.isEmpty ? 'None' : _userProfile.dietaryPreferences.join(', ')}";

    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userMessage}
    ];

    final requestBody = jsonEncode({
      'model': modelName,
      'messages': messages,
      'stream': false,
      'options': {'temperature': 0.7, 'num_ctx': 4096, 'num_predict': 512}
    });

    try {
      final response = await http
          .post(
            Uri.parse('$ollamaBaseUrl/api/chat'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: requestBody,
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final String? responseText = responseData['message']?['content'];

        if (responseText != null && responseText.isNotEmpty && mounted) {
          setState(() {
            _messages
                .add(ChatMessage(text: responseText.trim(), isUser: false));
          });
        } else {
          throw Exception('Empty response from model');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text:
                'Request timed out (90s). This might be due to slow network or heavy system load. Try a simpler question!',
            isUser: false,
            isError: true,
          ));
        });
      }
    } on SocketException {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _messages.add(ChatMessage(
            text:
                'Connection lost! Please check:\n• Ollama is still running\n• Same Wi-Fi network\n• Correct IP address',
            isUser: false,
            isError: true,
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text:
                'Failed to get response.\n\nEnsure:\n• Ollama is running\n• Model downloaded (ollama pull gemma2:2b)\n• Firewall allows port 11434',
            isUser: false,
            isError: true,
          ));
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _saveLocalIp(String ip) async {
    final ipv4Regex = RegExp(
        r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$');

    if (!ipv4Regex.hasMatch(ip)) {
      _showErrorDialog("Invalid IP Address",
          "Please enter a valid IPv4 address\n\nExample: 192.168.1.10");
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ollamaIp', ip);

      setState(() {
        ollamaBaseUrl = 'http://$ip:11434';
        _isConnected = false;
      });

      await _testConnection();
    } catch (e) {
      _showErrorDialog("Error", "Failed to save IP address: $e");
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFFF6B6B), size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Text(message, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF4ECDC4), size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Text(message, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Nutritionist'),
        actions: [
          if (_isConnected)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF4ECDC4).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Color(0xFF4ECDC4), size: 18),
                  SizedBox(width: 6),
                  Text('Connected',
                      style: TextStyle(
                          color: Color(0xFF4ECDC4),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
      backgroundColor: const Color(0xFFF8FAFB),
      body: Column(
        children: [
          // Connection Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isConnected
                    ? [
                        const Color(0xFF4ECDC4).withOpacity(0.1),
                        const Color(0xFF44A08D).withOpacity(0.1)
                      ]
                    : [
                        const Color(0xFFFFB75E).withOpacity(0.1),
                        const Color(0xFFED8F03).withOpacity(0.1)
                      ],
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  color: _isConnected
                      ? const Color(0xFF4ECDC4)
                      : const Color(0xFFED8F03),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isConnected
                        ? 'Connected to $ollamaBaseUrl'
                        : 'Not connected - Enter laptop IP below',
                    style: TextStyle(
                      fontSize: 13,
                      color: _isConnected
                          ? const Color(0xFF44A08D)
                          : const Color(0xFFED8F03),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // IP Input
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      hintText: 'Enter laptop IP (e.g., 192.168.1.10)',
                      prefixIcon: const Icon(Icons.computer_rounded, size: 22),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFB),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    enabled: !_isLoading,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF4ECDC4), Color(0xFF44A08D)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4ECDC4).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isLoading
                          ? null
                          : () => _saveLocalIp(_ipController.text.trim()),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Row(
                                children: [
                                  Icon(Icons.link_rounded,
                                      color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text('Connect',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Color(0xFF4ECDC4), Color(0xFF44A08D)]),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4ECDC4).withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.chat_bubble_rounded,
                              size: 48, color: Colors.white),
                        ),
                        const SizedBox(height: 24),
                        const Text('Connect to start chatting!',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A))),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index < _messages.length) {
                        return ChatBubble(message: _messages[index]);
                      } else {
                        return const LoadingBubble();
                      }
                    },
                  ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2))
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: _isConnected && !_isLoading,
                      decoration: InputDecoration(
                        hintText: _isConnected
                            ? 'Ask about nutrition...'
                            : 'Connect first...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        filled: true,
                        fillColor: _isConnected
                            ? const Color(0xFFF8FAFB)
                            : Colors.grey.shade100,
                      ),
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      gradient: (_isLoading || !_isConnected)
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFF4ECDC4), Color(0xFF44A08D)]),
                      color: (_isLoading || !_isConnected)
                          ? Colors.grey.shade300
                          : null,
                      shape: BoxShape.circle,
                      boxShadow: (_isLoading || !_isConnected)
                          ? null
                          : [
                              BoxShadow(
                                color: const Color(0xFF4ECDC4).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap:
                            (_isLoading || !_isConnected) ? null : _sendMessage,
                        borderRadius: BorderRadius.circular(28),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Chat Message Class ---
class ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;

  ChatMessage({required this.text, required this.isUser, this.isError = false});
}

// --- Chat Bubble ---
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isUser) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: message.isError
                    ? const LinearGradient(
                        colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)])
                    : const LinearGradient(
                        colors: [Color(0xFF4ECDC4), Color(0xFF44A08D)]),
                shape: BoxShape.circle,
              ),
              child: Icon(
                message.isError
                    ? Icons.error_outline_rounded
                    : Icons.psychology_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                gradient: message.isUser
                    ? const LinearGradient(
                        colors: [Color(0xFF00897B), Color(0xFF4DB6AC)])
                    : null,
                color: message.isUser
                    ? null
                    : (message.isError
                        ? const Color(0xFFFFEBEE)
                        : Colors.white),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: message.isUser
                      ? const Radius.circular(20)
                      : const Radius.circular(4),
                  bottomRight: message.isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: message.isUser
                        ? const Color(0xFF00897B).withOpacity(0.2)
                        : Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SelectableText(
                message.text,
                style: TextStyle(
                  color: message.isUser
                      ? Colors.white
                      : (message.isError
                          ? const Color(0xFFC62828)
                          : const Color(0xFF1A1A1A)),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFFE0F2F1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded,
                  color: Color(0xFF00897B), size: 20),
            ),
          ],
        ],
      ),
    );
  }
}

// --- Loading Bubble ---
class LoadingBubble extends StatelessWidget {
  const LoadingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF4ECDC4), Color(0xFF44A08D)]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.psychology_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child: const SizedBox(
              width: 40,
              height: 20,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF4ECDC4)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Health Insights Page ---
class HealthInsightsPage extends StatefulWidget {
  const HealthInsightsPage({super.key});

  @override
  State<HealthInsightsPage> createState() => _HealthInsightsPageState();
}

class _HealthInsightsPageState extends State<HealthInsightsPage> {
  String userName = 'User';
  String userGoal = 'Maintain health';
  List<String> healthConditions = [];
  List<String> dietaryPreferences = [];
  double bmi = 0;
  String bmiStatus = 'N/A';
  String dailyCalorieTarget = '2000';
  Map<String, String> macroTargets = {'protein': '50g', 'fat': '65g', 'carbs': '300g'};
  List<String> insights = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        userName = prefs.getString('name') ?? 'User';
        userGoal = prefs.getString('goal') ?? 'Maintain health';
        healthConditions = prefs.getStringList('healthConditions') ?? [];
        dietaryPreferences = prefs.getStringList('dietaryPreferences') ?? [];
      });
      _calculateHealthMetrics();
      _generateInsights();
    }
  }

  void _calculateHealthMetrics() {
    final prefs = SharedPreferences.getInstance();
    prefs.then((p) {
      final weight = double.tryParse(p.getString('weight') ?? '') ?? 0;
      final height = double.tryParse(p.getString('height') ?? '') ?? 0;

      if (weight > 0 && height > 0) {
        final heightInMeters = height / 100;
        final calculatedBmi = weight / (heightInMeters * heightInMeters);
        setState(() {
          bmi = double.parse(calculatedBmi.toStringAsFixed(1));
          bmiStatus = _getBmiStatus(bmi);
        });
      }

      // Calculate daily calorie target based on goal
      int target = 2000;
      if (userGoal == 'Weight Loss') target = 1800;
      if (userGoal == 'Weight Gain') target = 2500;
      if (userGoal == 'Muscle Building') target = 2300;

      setState(() {
        dailyCalorieTarget = target.toString();
      });
    });
  }

  String _getBmiStatus(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Normal Weight';
    if (bmi < 30) return 'Overweight';
    return 'Obese';
  }

  Color _getBmiColor(double bmi) {
    if (bmi < 18.5) return const Color(0xFF4ECDC4);
    if (bmi < 25) return const Color(0xFF56AB2F);
    if (bmi < 30) return const Color(0xFFED8F03);
    return const Color(0xFFFF6B6B);
  }

  void _generateInsights() {
    List<String> newInsights = [];

    // BMI insights
    if (bmi > 0) {
      if (bmiStatus == 'Underweight') {
        newInsights.add('📈 You are underweight. Focus on nutrient-dense foods and increase calorie intake.');
      } else if (bmiStatus == 'Overweight' || bmiStatus == 'Obese') {
        newInsights.add('💪 Increase protein intake to 1.6g per kg of body weight and include strength training.');
      }
    }

    // Condition-based insights
    if (healthConditions.contains('Type 2 Diabetes')) {
      newInsights.add('🍎 Reduce refined carbs. Focus on whole grains, legumes, and vegetables.');
    }
    if (healthConditions.contains('Hypertension (High BP)')) {
      newInsights.add('🧂 Limit sodium intake. Aim for <2300mg per day.');
    }
    if (healthConditions.contains('High Cholesterol')) {
      newInsights.add('❤️ Increase soluble fiber (oats, beans) and omega-3s (fish, flaxseed).');
    }
    if (healthConditions.contains('PCOS')) {
      newInsights.add('🥗 Include anti-inflammatory foods: berries, leafy greens, nuts. Avoid refined sugars.');
    }

    // Goal-based insights
    if (userGoal == 'Weight Loss') {
      newInsights.add('⚖️ Create a 500 kcal deficit daily for 0.5 kg/week weight loss.');
    }
    if (userGoal == 'Muscle Building') {
      newInsights.add('🏋️ Eat 1.6-2.2g protein per kg of body weight and train with resistance.');
    }

    // Dietary preference insights
    if (dietaryPreferences.contains('Vegetarian') || dietaryPreferences.contains('Vegan')) {
      newInsights.add('🌿 Combine legumes with grains for complete proteins. Use fortified plant-based milk.');
    }

    if (newInsights.isEmpty) {
      newInsights.add('✨ Keep up your healthy lifestyle! Stay consistent with balanced meals.');
    }

    setState(() {
      insights = newInsights;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Insights'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF667EEA).withValues(alpha: 0.05),
                Colors.transparent
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // BMI Card
            if (bmi > 0)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _getBmiColor(bmi).withValues(alpha: 0.1),
                      _getBmiColor(bmi).withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _getBmiColor(bmi).withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [_getBmiColor(bmi), _getBmiColor(bmi).withValues(alpha: 0.7)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _getBmiColor(bmi).withValues(alpha: 0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            bmi.toString(),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Text(
                            'BMI',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bmiStatus,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _getBmiColor(bmi),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your current body mass index',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _getBmiColor(bmi).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '📊 Healthy BMI: 18.5 - 24.9',
                              style: TextStyle(
                                fontSize: 12,
                                color: _getBmiColor(bmi),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // Daily Calorie Target
            Text(
              'Daily Nutrition Targets',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.local_fire_department_rounded,
                          color: Color(0xFFFF6B6B),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Daily Calories',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '$dailyCalorieTarget kcal',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  _buildMacroTarget('Protein', macroTargets['protein'] ?? 'N/A', const Color(0xFF4ECDC4)),
                  const SizedBox(height: 12),
                  _buildMacroTarget('Fat', macroTargets['fat'] ?? 'N/A', const Color(0xFFFFB75E)),
                  const SizedBox(height: 12),
                  _buildMacroTarget('Carbs', macroTargets['carbs'] ?? 'N/A', const Color(0xFF667EEA)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Personalized Insights
            Text(
              'Your Personalized Insights',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            ...insights.map((insight) => _buildInsightCard(insight)).toList(),
            const SizedBox(height: 32),

            // Health Conditions Summary
            if (healthConditions.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Health Conditions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: healthConditions.map((condition) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B).withValues(alpha: 0.1),
                          border: Border.all(
                            color: const Color(0xFFFF6B6B).withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '⚕️ $condition',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFFF6B6B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroTarget(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildInsightCard(String insight) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Text(
        insight,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[800],
          height: 1.6,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// --- Beautiful Profile Page ---
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = '';
  String age = '';
  String weight = '';
  String height = '';
  String selectedGender = 'Prefer not to say';
  List<String> healthConditions = [];
  List<String> dietaryPreferences = [];
  String goal = 'Maintain health';

  final List<String> conditionOptions = [
    'Type 2 Diabetes',
    'Type 1 Diabetes',
    'Hypertension (High BP)',
    'Heart Disease',
    'PCOS',
    'Thyroid Disorder',
    'High Cholesterol',
    'Kidney Disease',
    'None',
  ];

  final List<String> preferenceOptions = [
    'Vegetarian',
    'Vegan',
    'Non-vegetarian',
    'Eggetarian',
    'Jain',
    'Dairy-free',
    'Gluten-free',
    'Nut Allergy',
  ];

  final List<String> goalOptions = [
    'Weight Loss',
    'Weight Gain',
    'Muscle Building',
    'Maintain health',
    'Manage diabetes',
    'Improve heart health',
    'Better digestion',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        name = prefs.getString('name') ?? '';
        age = prefs.getString('age') ?? '';
        weight = prefs.getString('weight') ?? '';
        height = prefs.getString('height') ?? '';
        selectedGender = prefs.getString('gender') ?? 'Prefer not to say';
        healthConditions = prefs.getStringList('healthConditions') ?? [];
        dietaryPreferences = prefs.getStringList('dietaryPreferences') ?? [];
        goal = prefs.getString('goal') ?? 'Maintain health';
      });
    }
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', name);
    await prefs.setString('age', age);
    await prefs.setString('weight', weight);
    await prefs.setString('height', height);
    await prefs.setString('gender', selectedGender);
    await prefs.setStringList('healthConditions', healthConditions);
    await prefs.setStringList('dietaryPreferences', dietaryPreferences);
    await prefs.setString('goal', goal);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text('Profile saved successfully!',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          backgroundColor: const Color(0xFF4ECDC4),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF00897B).withOpacity(0.05),
                Colors.transparent
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Avatar
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF00897B), Color(0xFF4DB6AC)]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00897B).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(Icons.person_rounded,
                    size: 50, color: Colors.white),
              ),
            ),
            const SizedBox(height: 32),

            // Basic Info Section
            _buildSectionTitle('Basic Information'),
            const SizedBox(height: 16),
            _buildTextField('Name', name, (val) => setState(() => name = val)),
            const SizedBox(height: 12),
            _buildTextField('Age', age, (val) => setState(() => age = val),
                keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _buildTextField(
                'Weight (kg)', weight, (val) => setState(() => weight = val),
                keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _buildTextField(
                'Height (cm)', height, (val) => setState(() => height = val),
                keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            _buildGenderSelector(),
            const SizedBox(height: 32),

            // Health Goal Section
            _buildSectionTitle('Health Goal'),
            const SizedBox(height: 16),
            _buildGoalSelector(),
            const SizedBox(height: 32),

            // Health Conditions Section
            _buildSectionTitle('Health Conditions'),
            const SizedBox(height: 16),
            _buildMultiSelectChips(conditionOptions, healthConditions,
                (selected) {
              setState(() => healthConditions = selected);
            }),
            const SizedBox(height: 32),

            // Dietary Preferences Section
            _buildSectionTitle('Dietary Preferences'),
            const SizedBox(height: 16),
            _buildMultiSelectChips(preferenceOptions, dietaryPreferences,
                (selected) {
              setState(() => dietaryPreferences = selected);
            }),
            const SizedBox(height: 32),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF00897B), Color(0xFF4DB6AC)]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    alignment: Alignment.center,
                    constraints: const BoxConstraints(minHeight: 50),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save_rounded, color: Colors.white),
                        SizedBox(width: 12),
                        Text(
                          'Save Profile',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
    );
  }

  Widget _buildTextField(String label, String value, Function(String) onChanged,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: TextEditingController(text: value)
        ..selection = TextSelection.collapsed(offset: value.length),
      onChanged: onChanged,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gender',
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: ['Male', 'Female', 'Prefer not to say'].map((gender) {
              final isSelected = selectedGender == gender;
              return ChoiceChip(
                label: Text(gender),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) setState(() => selectedGender = gender);
                },
                selectedColor: const Color(0xFF00897B).withOpacity(0.2),
                backgroundColor: Colors.grey.shade100,
                labelStyle: TextStyle(
                  color:
                      isSelected ? const Color(0xFF00897B) : Colors.grey[700],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonFormField<String>(
        value: goal,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        items: goalOptions
            .map((g) => DropdownMenuItem(value: g, child: Text(g)))
            .toList(),
        onChanged: (val) {
          if (val != null) setState(() => goal = val);
        },
      ),
    );
  }

  Widget _buildMultiSelectChips(List<String> options, List<String> selected,
      Function(List<String>) onChanged) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = selected.contains(option);
        return FilterChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (bool value) {
            List<String> newSelected = List.from(selected);
            if (value) {
              newSelected.add(option);
            } else {
              newSelected.remove(option);
            }
            onChanged(newSelected);
          },
          selectedColor: const Color(0xFF00897B).withOpacity(0.2),
          backgroundColor: Colors.white,
          checkmarkColor: const Color(0xFF00897B),
          labelStyle: TextStyle(
            color: isSelected ? const Color(0xFF00897B) : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
          side: BorderSide(
              color:
                  isSelected ? const Color(0xFF00897B) : Colors.grey.shade300),
        );
      }).toList(),
    );
  }
}

// --- Meal History Page ---
class MealHistoryPage extends StatefulWidget {
  const MealHistoryPage({super.key});

  @override
  State<MealHistoryPage> createState() => _MealHistoryPageState();
}

class _MealHistoryPageState extends State<MealHistoryPage> {
  List<Map<String, dynamic>> meals = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMeals();
  }

  Future<void> _loadMeals() async {
    final data = await DatabaseHelper.instance.getRecentMeals(30);
    if (mounted) {
      setState(() {
        meals = data;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meal History')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : meals.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.restaurant_menu,
                          size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No meals logged yet',
                          style: TextStyle(
                              fontSize: 18, color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      Text('Scan your first meal to get started!',
                          style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: meals.length,
                  itemBuilder: (context, index) {
                    final meal = meals[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00897B).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(_getMealIcon(meal['meal_type']),
                              color: const Color(0xFF00897B)),
                        ),
                        title: Text(meal['name'],
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${meal['meal_type']} • ${meal['date']}\n${meal['calories'].round()} kcal'),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () async {
                            await DatabaseHelper.instance
                                .deleteMeal(meal['id']);
                            _loadMeals();
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  IconData _getMealIcon(String mealType) {
    switch (mealType) {
      case 'Breakfast':
        return Icons.breakfast_dining_rounded;
      case 'Lunch':
        return Icons.lunch_dining_rounded;
      case 'Dinner':
        return Icons.dinner_dining_rounded;
      case 'Snack':
        return Icons.fastfood_rounded;
      default:
        return Icons.restaurant_rounded;
    }
  }
}

// --- Analytics Page ---
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  List<Map<String, dynamic>> weekData = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWeekData();
  }

  Future<void> _loadWeekData() async {
    final meals = await DatabaseHelper.instance.getRecentMeals(7);
    Map<String, Map<String, double>> dailyTotals = {};

    for (var meal in meals) {
      final date = meal['date'];
      if (!dailyTotals.containsKey(date)) {
        dailyTotals[date] = {'calories': 0, 'protein': 0, 'fat': 0, 'carbs': 0};
      }
      dailyTotals[date]!['calories'] =
          (dailyTotals[date]!['calories']! + meal['calories']);
      dailyTotals[date]!['protein'] =
          (dailyTotals[date]!['protein']! + meal['protein']);
      dailyTotals[date]!['fat'] = (dailyTotals[date]!['fat']! + meal['fat']);
      dailyTotals[date]!['carbs'] =
          (dailyTotals[date]!['carbs']! + meal['carbs']);
    }

    if (mounted) {
      setState(() {
        weekData = dailyTotals.entries
            .map((e) => {'date': e.key, ...e.value})
            .toList();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : weekData.isEmpty
              ? const Center(child: Text('No data yet. Start logging meals!'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('7-Day Calorie Trend',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Container(
                        height: 250,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: false),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    if (value.toInt() < weekData.length) {
                                      return Text(DateFormat('E').format(
                                          DateTime.parse(weekData[value.toInt()]
                                              ['date'])));
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: weekData
                                    .asMap()
                                    .entries
                                    .map((e) => FlSpot(
                                        e.key.toDouble(), e.value['calories']!))
                                    .toList(),
                                isCurved: true,
                                color: const Color(0xFF00897B),
                                barWidth: 3,
                                dotData: const FlDotData(show: true),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text('Average Daily Intake',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      _buildAverageTile(
                          'Calories',
                          _calculateAverage('calories'),
                          'kcal',
                          Icons.local_fire_department_rounded),
                      _buildAverageTile('Protein', _calculateAverage('protein'),
                          'g', Icons.fitness_center_rounded),
                      _buildAverageTile('Carbs', _calculateAverage('carbs'),
                          'g', Icons.grain_rounded),
                      _buildAverageTile('Fat', _calculateAverage('fat'), 'g',
                          Icons.water_drop_rounded),
                    ],
                  ),
                ),
    );
  }

  double _calculateAverage(String nutrient) {
    if (weekData.isEmpty) return 0;
    double total = weekData.fold(0, (sum, day) => sum + day[nutrient]!);
    return total / weekData.length;
  }

  Widget _buildAverageTile(
      String label, double value, String unit, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00897B)),
          const SizedBox(width: 16),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600))),
          Text('${value.toStringAsFixed(1)} $unit',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
