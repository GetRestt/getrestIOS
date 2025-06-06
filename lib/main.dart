import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

  Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp();
  }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
   late WebViewController _controller;
  InAppWebViewController? _inAppWebViewController;
  double _progress = 0;
  bool _isLoading = true;
  bool _isFirstLoad = true;
  bool _isError = false;
  bool _isServerError = false;
  String _currentUrl = "https://getrestt.com";
  bool _useFlutterWebView = false;
  late final FirebaseMessaging _messaging;
  String? _fcmToken;
  String get mobileUserAgent {
    return Platform.isIOS
       ? "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/537.36"
        : "Mozilla/5.0 (Linux; Android 10; Mobile; rv:89.0) Gecko/89.0 Firefox/89.0";
  }
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _loadLastUrl();
    _initFirebaseMessaging();
    _initWebViewController();
  }
  
 void _initWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(mobileUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
           onNavigationRequest: (NavigationRequest request) async {
          if (request.url.startsWith("kcbconsumer://")) {
            // Launch custom scheme using url_launcher
            if (await canLaunchUrl(Uri.parse(request.url))) {
              await launchUrl(Uri.parse(request.url));
            } else {
            }
            return NavigationDecision.prevent; // Don't let WebView load it
          }
          return NavigationDecision.navigate;
        },
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _progress = 0.1;
              _isError = false;
              _isServerError = false;
              _currentUrl = url;
            });
          },
          onProgress: (progress) {
            setState(() {
              _progress = progress / 100;
            });
          },
          onPageFinished: (url) async {
            final result = await _controller.runJavaScriptReturningResult('navigator.userAgent');
            setState(() {
              _isLoading = false;
              _progress = 1.0;
              _currentUrl = url;
              _useFlutterWebView = _currentUrl
                  .contains("https://getrestt.com/talent-registration/create");
              if(_useFlutterWebView){
                _inAppWebViewController?.loadUrl(urlRequest: URLRequest(url: Uri.parse(_currentUrl)));
              }

            });
            await _saveCurrentUrl(url);
            try {
              String? bodyText = await _controller.runJavaScriptReturningResult(
                "document.body.innerText",
              ) as String?;

              if (bodyText != null &&
                  (bodyText.contains("500 Internal Server Error") ||
                      bodyText.contains("Server Error in '/' Application."))) {
                setState(() {
                  _isServerError = true;
                });
              }
            } catch (_) {}
          },
          onWebResourceError: (error) {
            setState(() {
              _isError = true;
            });
          },
        ),
      )
      ..addJavaScriptChannel(
        'userLoggedIn',
        onMessageReceived: (JavaScriptMessage message) {
          final data = jsonDecode(message.message);
          final userId = data['user_id'];
          _sendFcmTokenToLaravel(_fcmToken, userId);
        },
      )
      ..loadRequest(Uri.parse(_currentUrl));
  }
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
      const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
  const iOSInit = DarwinInitializationSettings();
  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: iOSInit,
  );
    await _flutterLocalNotificationsPlugin.initialize(initSettings);

    _messaging = FirebaseMessaging.instance;
    await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
    );

    try {
    final token = await _messaging.getToken();
    if (token != null) {
      setState(() => _fcmToken = token);
    } else {
       setState(() {
        _fcmToken = null; // Optional: Set a fallback value
      });
    }
  } catch (e) {
     setState(() {
      _fcmToken = null; // Optional: Set a fallback value
    });
  }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        _useFlutterWebView=true;
        _inAppWebViewController?.loadUrl(urlRequest: URLRequest(url: Uri.parse(_currentUrl)));
        _showLocalNotification(notification.title, notification.body);
        _useFlutterWebView=false;
      }
    });

     // App opened from terminated/background via notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        _useFlutterWebView=true;
        _inAppWebViewController?.loadUrl(urlRequest: URLRequest(url: Uri.parse(_currentUrl)));
        _showLocalNotification(notification.title, notification.body);
        _useFlutterWebView=false;
      }
      // Optional: Add navigation or data handling here
    });

    // Register background message handler (should be at top-level)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    
  }

  void _showLocalNotification(String? title, String? body) {
    const androidDetails = AndroidNotificationDetails(
      'default_channel',
      'Default',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );

    const platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    _flutterLocalNotificationsPlugin.show(0, title, body, platformDetails);
  }

  Future<void> _loadLastUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('last_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      setState(() => _currentUrl = savedUrl);
    }
  }

  Future<void> _saveCurrentUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_url', url);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (!didPop && _controller != null && await _controller.canGoBack()) {
          _controller.goBack();
        }
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(4.0),
          child: _isLoading
              ? LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.white,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                )
              : const SizedBox(height: 4.0),
        ),
        body: Stack(
          children: [
            SafeArea(
              child: (!_isError && !_isServerError) 
              ? (_useFlutterWebView ? InAppWebView(
                initialUrlRequest: URLRequest(url: Uri.parse("https://getrestt.com")),
                initialOptions: InAppWebViewGroupOptions(
                  crossPlatform: InAppWebViewOptions(
                    javaScriptEnabled: true,
                    useShouldOverrideUrlLoading: true,
                    mediaPlaybackRequiresUserGesture: false,
                     userAgent: Platform.isIOS
                        ? "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/537.36"
                        : "Mozilla/5.0 (Linux; Android 10; Mobile; rv:89.0) Gecko/89.0 Firefox/89.0",
                  ),
                ),
                onWebViewCreated: (controller) {
                  _inAppWebViewController = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'userLoggedIn',
                    callback: (args) {
                      final userId = args[0]['user_id'];
                      if (_fcmToken != null) {
                        _sendFcmTokenToLaravel(_fcmToken, userId);
                      }
                    },
                  );
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
                    await _saveCurrentUrl(_currentUrl);
              
                    if (_isFirstLoad) {
                      setState(() => _isFirstLoad = false);
                    }
              
                    String? bodyText = await controller.evaluateJavascript(
                      source: "document.body.innerText",
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
                  setState(() {
                    _isError = true;
                  });
                },
                onLoadHttpError: (controller, url, statusCode, description) {
                  setState(() {
                    _isError = true;
                  });
                }, 
              ) : WebViewWidget(controller: _controller) )
              : const SizedBox.shrink(),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blueGrey.shade900,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text("Try Again", style: TextStyle(fontSize: 18)),
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
    _controller.loadRequest(Uri.parse(_currentUrl));
    //_controller?.loadUrl(urlRequest: URLRequest(url: Uri.parse(_currentUrl)));
  }

  void _reloadPage() {
    setState(() {
      _isError = false;
      _isServerError = false;
      _isLoading = true;
    });
    _controller.reload();
    //_controller?.reload();
  }
}
