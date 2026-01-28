import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:whisper_space_flutter/core/providers/theme_provider.dart';
import 'package:whisper_space_flutter/core/services/auth_service.dart';
import 'package:whisper_space_flutter/core/services/storage_service.dart';
import 'package:whisper_space_flutter/features/auth/presentation/screens/home_screen.dart';
import 'package:whisper_space_flutter/features/auth/presentation/screens/login_screen.dart';
import 'package:whisper_space_flutter/features/auth/presentation/screens/providers/auth_provider.dart';
import 'package:whisper_space_flutter/features/feed/data/datasources/feed_api_service.dart';
import 'package:whisper_space_flutter/features/feed/presentation/providers/feed_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  
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
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
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
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF7C3AED),
            brightness: Brightness.light,
          ),
        ),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'App failed to start',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Error: $e',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: () {
                      // You could add a restart mechanism here
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        // Set status bar color based on theme
        SystemChrome.setSystemUIOverlayStyle(
          themeProvider.isDarkMode
              ? SystemUiOverlayStyle.light.copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: const Color(0xFF111827),
                  systemNavigationBarIconBrightness: Brightness.light,
                )
              : SystemUiOverlayStyle.dark.copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.white,
                  systemNavigationBarIconBrightness: Brightness.dark,
                ),
        );
        
        return MaterialApp(
          title: 'Whisper Space',
          debugShowCheckedModeBanner: false,
          theme: themeProvider.currentTheme,
          themeMode: themeProvider.themeMode,
          builder: (context, child) {
            return ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: true,
                overscroll: false,
              ),
              child: SafeArea(
                child: child!,
              ),
            );
          },
          home: Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              if (authProvider.isLoading) {
                return _buildLoadingScreen(themeProvider);
              }
              
              if (authProvider.currentUser != null) {
                return const HomeScreen();
              } else {
                return const LoginScreen();
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildLoadingScreen(ThemeProvider themeProvider) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: themeProvider.isDarkMode
              ? const LinearGradient(
                  colors: [Color(0xFF111827), Color(0xFF1F2937)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : const LinearGradient(
                  colors: [Color(0xFFF9FAFB), Color(0xFFE5E7EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated logo/icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 1000),
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: themeProvider.isDarkMode
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFF7C3AED),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: themeProvider.isDarkMode
                          ? const Color(0xFF7C3AED).withOpacity(0.3)
                          : const Color(0xFF7C3AED).withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.message,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                'Whisper Space',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Loading your space...',
                style: TextStyle(
                  fontSize: 16,
                  color: themeProvider.isDarkMode
                      ? Colors.grey[400]
                      : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    themeProvider.isDarkMode
                        ? const Color(0xFFA78BFA)
                        : const Color(0xFF7C3AED),
                  ),
                  backgroundColor: themeProvider.isDarkMode
                      ? Colors.white.withOpacity(0.1)
                      : Colors.grey[200],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}