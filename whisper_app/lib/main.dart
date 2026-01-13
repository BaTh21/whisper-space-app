// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:whisper_space_flutter/core/services/auth_service.dart';
import 'package:whisper_space_flutter/core/services/storage_service.dart';
import 'package:whisper_space_flutter/features/auth/presentation/screens/home_screen.dart';
import 'package:whisper_space_flutter/features/auth/presentation/screens/login_screen.dart';
import 'package:whisper_space_flutter/features/auth/presentation/screens/providers/auth_provider.dart';
import 'package:whisper_space_flutter/features/feed/data/datasources/feed_api_service.dart';
import 'package:whisper_space_flutter/features/feed/presentation/providers/feed_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize storage service
    final storageService = StorageService();
    await storageService.init();
    
    // Initialize other services
    final authService = AuthService(storageService: storageService);
    final feedApiService = FeedApiService(storageService: storageService);
    
    runApp(
      MultiProvider(
        providers: [
          Provider<StorageService>(create: (_) => storageService),
          Provider<AuthService>(create: (_) => authService),
          Provider<FeedApiService>(create: (_) => feedApiService),
          ChangeNotifierProvider(
            create: (context) => AuthProvider(
              authService: authService,
              storageService: storageService,
            ),
          ),
          ChangeNotifierProvider(
            create: (context) => FeedProvider(feedApiService: feedApiService),
          ),
        ],
        child: const MyApp(),
      ),
    );
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('App failed to start: $e'),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Whisper Space',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF6C63FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          if (authProvider.isLoading) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    Text('Loading app...', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            );
          }
          
          if (authProvider.currentUser != null) {
            return const HomeScreen();
          } else {
            return const LoginScreen();
          }
        },
      ),
    );
  }
}