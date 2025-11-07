import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity_data.dart';
import 'fit_file_generator.dart';

/// Strava API integration service
/// Setup: Create app at https://www.strava.com/settings/api
class StravaService {
  // TODO: Get these from Strava Developer Portal
  static const String CLIENT_ID = '18166';
  static const String CLIENT_SECRET = '6dfb4cdf0bf055268099e981d69bdb5c76662760';
  static const String REDIRECT_URI = 'spinworkout://oauth';

  static const String AUTH_URL = 'https://www.strava.com/oauth/authorize';
  static const String TOKEN_URL = 'https://www.strava.com/oauth/token';
  static const String API_URL = 'https://www.strava.com/api/v3';

  String? _accessToken;
  DateTime? _tokenExpiry;

  bool get isAuthenticated => _accessToken != null &&
      _tokenExpiry != null &&
      DateTime.now().isBefore(_tokenExpiry!);

  /// Start OAuth flow
  Future<bool> authenticate() async {
    try {
      // Build authorization URL
      final authUrl = Uri.parse(AUTH_URL).replace(queryParameters: {
        'client_id': CLIENT_ID,
        'redirect_uri': REDIRECT_URI,
        'response_type': 'code',
        'scope': 'activity:write,activity:read_all',
        'approval_prompt': 'auto',
      });

      // Launch browser
      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
        return true;
      } else {
        throw Exception('Could not launch browser');
      }
    } catch (e) {
      throw Exception('OAuth error: $e');
    }
  }

  /// Handle OAuth callback (call this from deep link handler)
  Future<bool> handleAuthCallback(String code) async {
    try {
      final response = await http.post(
        Uri.parse(TOKEN_URL),
        body: {
          'client_id': CLIENT_ID,
          'client_secret': CLIENT_SECRET,
          'code': code,
          'grant_type': 'authorization_code',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _tokenExpiry = DateTime.now().add(Duration(seconds: data['expires_in']));

        // Save tokens
        await _saveTokens(data['access_token'], data['refresh_token']);

        return true;
      } else {
        throw Exception('Token exchange failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('Callback handling error: $e');
    }
  }

  /// Refresh access token
  Future<bool> refreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('strava_refresh_token');

      if (refreshToken == null) {
        return false;
      }

      final response = await http.post(
        Uri.parse(TOKEN_URL),
        body: {
          'client_id': CLIENT_ID,
          'client_secret': CLIENT_SECRET,
          'refresh_token': refreshToken,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _tokenExpiry = DateTime.now().add(Duration(seconds: data['expires_in']));

        await _saveTokens(data['access_token'], data['refresh_token']);

        return true;
      }

      return false;
    } catch (e) {
      print('Token refresh error: $e');
      return false;
    }
  }

  /// Upload activity to Strava
  Future<String> uploadActivity(ActivityData activity) async {
    // Ensure we have valid token
    if (!isAuthenticated) {
      final refreshed = await refreshToken();
      if (!refreshed) {
        throw Exception('Not authenticated. Please login to Strava.');
      }
    }

    try {
      // Generate FIT file
      final fitFilePath = await FitFileGenerator.generateFitFile(activity);
      final fitFile = File(fitFilePath);

      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$API_URL/uploads'),
      );

      request.headers['Authorization'] = 'Bearer $_accessToken';
      request.fields['data_type'] = 'fit';
      request.fields['name'] = activity.workoutName;
      request.fields['description'] = 'Indoor cycling workout\n\n'
          'Duration: ${activity.formattedDuration}\n'
          'Avg HR: ${activity.avgHeartRate} bpm\n'
          'Avg Power: ${activity.avgPower.round()}W\n'
          'TSS: ${activity.tss.round()}\n\n'
          'Created with Spinning Workout App';
      request.fields['trainer'] = '1'; // Mark as trainer/indoor
      request.fields['activity_type'] = 'VirtualRide';

      // Add FIT file
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        fitFilePath,
      ));

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final uploadId = data['id'];

        // Wait for processing (optional)
        await _waitForUpload(uploadId);

        // Clean up FIT file
        await fitFile.delete();

        return data['activity_id']?.toString() ?? uploadId.toString();
      } else {
        throw Exception('Upload failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('Upload error: $e');
    }
  }

  /// Wait for upload to be processed
  Future<void> _waitForUpload(int uploadId) async {
    for (var i = 0; i < 30; i++) {
      // Try for 30 seconds
      await Future.delayed(const Duration(seconds: 1));

      try {
        final response = await http.get(
          Uri.parse('$API_URL/uploads/$uploadId'),
          headers: {'Authorization': 'Bearer $_accessToken'},
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['activity_id'] != null) {
            return; // Upload complete
          }
        }
      } catch (e) {
        // Continue waiting
      }
    }
  }

  /// Get athlete profile
  Future<Map<String, dynamic>> getAthlete() async {
    if (!isAuthenticated) {
      throw Exception('Not authenticated');
    }

    try {
      final response = await http.get(
        Uri.parse('$API_URL/athlete'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to get athlete: ${response.body}');
      }
    } catch (e) {
      throw Exception('Get athlete error: $e');
    }
  }

  /// Save tokens to local storage
  Future<void> _saveTokens(String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('strava_access_token', accessToken);
    await prefs.setString('strava_refresh_token', refreshToken);
  }

  /// Load saved tokens
  Future<void> loadSavedTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('strava_access_token');

    // Try to refresh if we have refresh token
    if (_accessToken != null) {
      await refreshToken();
    }
  }

  /// Logout
  Future<void> logout() async {
    _accessToken = null;
    _tokenExpiry = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('strava_access_token');
    await prefs.remove('strava_refresh_token');
  }
}
