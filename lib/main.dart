import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

  Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
  }


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase initialization
  await Firebase.initializeApp();

  // Register background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  if (Platform.isAndroid) {
    await AndroidInAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({Key? key}) : super(key: key);

  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _isLoading = true;
  final bool _isFirstLoad = true;
  bool _isError = false;
  bool _isServerError = false;
  String _currentUrl = "https://getrestt.com/";
  late final FirebaseMessaging _messaging;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  String get mobileUserAgent {
    return Platform.isIOS
        ? "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/537.36"
        : "Mozilla/5.0 (Linux; Android 10; Mobile; rv:89.0) Gecko/89.0 Firefox/89.0";
  }

  @override
  void initState() {
    super.initState();
    _loadLastUrl();
    _initFirebaseMessaging();
  }

  String? _fcmToken;

  void _sendFcmTokenToLaravel(String? token, int userId) async {
    if (token == null) return;

     await http.post(
      Uri.parse("https://getrestt.com/save-fcm-token"),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        "fcm_token": token,
        "user_id": userId,
      }),
    );
  }

  void _initFirebaseMessaging() async {
    // Android init
    const AndroidInitializationSettings androidInitSettings =
        AndroidInitializationSettings('@drawable/ic_notification');

    // iOS init
    const DarwinInitializationSettings iOSInit =
        DarwinInitializationSettings();

    // Combined settings
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInitSettings,
      iOS: iOSInit,
    );

    await _flutterLocalNotificationsPlugin.initialize(initSettings);

    _messaging = FirebaseMessaging.instance;

    // Request permission (iOS)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    _fcmToken = await _messaging.getToken();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      if (notification != null) {
        _showLocalNotification(notification.title, notification.body);
      }
    });

    // App opened from terminated or background via notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      if (notification != null) {
        _showLocalNotification(notification.title, notification.body);
      }
    });

  }

  void _showLocalNotification(String? title, String? body) {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'default_channel',
      'Default',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    _flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformDetails,
    );
  }

  Future<void> _loadLastUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('last_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      setState(() {
        _currentUrl = savedUrl;
      });
    }
  }

  Future<void> _saveCurrentUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_url', url);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Uri? uri = await _controller!.getUrl();
        if (_controller != null &&
            await _controller!.canGoBack() &&
            uri!.toString().startsWith('https://getrestt.com')) {
          _controller!.goBack();
          return false;
        } else {
          final prefs = await SharedPreferences.getInstance();
          final savedUrl = prefs.getString('last_url');
          if (savedUrl != null && savedUrl.isNotEmpty) {
            _controller?.loadUrl(
                urlRequest: URLRequest(url: Uri.parse(savedUrl)));
          }
          return false;
        }
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: _isLoading
              ? LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                )
              : const SizedBox(height: 4.0),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              if (!_isError && !_isServerError)
                InAppWebView(
                  initialUrlRequest:
                      URLRequest(url: Uri.parse(_currentUrl)),
                  initialOptions: InAppWebViewGroupOptions(
                    crossPlatform: InAppWebViewOptions(
                      javaScriptEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      mediaPlaybackRequiresUserGesture: false,
                    ),
                    android: AndroidInAppWebViewOptions(
                      useHybridComposition: true,
                    ),
                    ios: IOSInAppWebViewOptions(
                      allowsInlineMediaPlayback: true,
                      allowsBackForwardNavigationGestures: true,
                      sharedCookiesEnabled: true,
                    ),
                  ),
                  onWebViewCreated: (controller) {
                    _controller = controller;
                    controller.addJavaScriptHandler(
                      handlerName: 'userLoggedIn',
                      callback: (args) {
                        final userId = args[0]['user_id'];
                        _sendFcmTokenToLaravel(_fcmToken, userId);
                      },
                    );
                  },
                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                    final url = navigationAction.request.url.toString();

                    if (url.startsWith("https://superapp.ethiomobilemoney.et")) {
                    }

                    if (url.startsWith("kcbconsumer://")) {
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onLoadStart: (controller, url) {
                    if (url != null) {
                      setState(() {
                        _isLoading = true;
                        _progress = 0.1;
                        _isServerError = false;
                        _currentUrl = url.toString();
                      });
                    }
                  },
                  onLoadStop: (controller, url) async {
                    if (url != null) {        
                      setState(() {
                        _isLoading = false;
                        _progress = 1.0;
                        _currentUrl = url.toString();
                      });
                      if (url.toString().startsWith('https://getrestt.com')) {
                        await _saveCurrentUrl(_currentUrl);
                      }

                      String? bodyText = await controller.evaluateJavascript(
                        source: """document.body.innerText""",
                      );

                      if (bodyText != null &&
                          (bodyText.contains("500 Internal Server Error") ||
                              bodyText.contains("Server Error in '/' Application."))) {
                        setState(() {
                          _isServerError = true;
                        });
                      }
                    }
                  },
                  onProgressChanged: (controller, progress) {
                    setState(() {
                      _progress = progress / 100;
                    });
                  },
                  onLoadError: (controller, url, code, message) {
                    if (code == -2 || code == -105) {
                      setState(() {
                        _isError = true;
                      });
                    }
                  },
                ),
              if (_isFirstLoad && _isLoading)
                Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.orange.withOpacity(0.5),
                    ),
                  ),
                ),
              if (_isError)
                _buildErrorScreen("Please check your internet!", _reloadPage),
              if (_isServerError)
                _buildErrorScreen("Server Error. Try again now!", _reloadCurrentUrl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen(String message, VoidCallback onRetry) {
    return Positioned.fill(
      child: Container(
        color: Colors.blueGrey.shade900,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.white, size: 80),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text("Try Again", style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blueGrey.shade900,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _reloadCurrentUrl() {
    setState(() {
      _isError = false;
      _isServerError = false;
      _isLoading = true;
    });
    _controller?.loadUrl(urlRequest: URLRequest(url: Uri.parse(_currentUrl)));
  }

  void _reloadPage() {
    setState(() {
      _isError = false;
      _isServerError = false;
      _isLoading = true;
    });
    _controller?.reload();
  }
}
