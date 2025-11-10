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
        'approval_prompt': 'force', // Force to ensure we get the right scope
      });

      print('Auth URL: $authUrl');
      print('Requested scope: activity:write,activity:read_all');

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
      print('Exchanging code for token...');
      final response = await http.post(
        Uri.parse(TOKEN_URL),
        body: {
          'client_id': CLIENT_ID,
          'client_secret': CLIENT_SECRET,
          'code': code,
          'grant_type': 'authorization_code',
        },
      );

      print('Token response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _tokenExpiry = DateTime.now().add(Duration(seconds: data['expires_in']));

        // Log athlete info and scope
        print('=== STRAVA AUTH SUCCESS ===');
        print('Athlete: ${data['athlete']?['firstname']} ${data['athlete']?['lastname']} (ID: ${data['athlete']?['id']})');
        print('Scope granted: ${data['scope']}');
        print('Token expires in: ${data['expires_in']} seconds');
        print('==========================');

        // Save tokens
        await _saveTokens(data['access_token'], data['refresh_token']);

        return true;
      } else {
        print('Token exchange failed: ${response.body}');
        throw Exception('Token exchange failed: ${response.body}');
      }
    } catch (e) {
      print('Callback handling error: $e');
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
      print('=== STARTING STRAVA UPLOAD ===');

      // Generate FIT file
      print('Generating FIT file...');
      final fitFilePath = await FitFileGenerator.generateFitFile(activity);
      final fitFile = File(fitFilePath);
      final fitFileSize = await fitFile.length();
      print('FIT file created: $fitFilePath ($fitFileSize bytes)');

      // Log activity details
      print('Activity details:');
      print('  - Name: ${activity.workoutName}');
      print('  - Duration: ${activity.durationSeconds}s');
      print('  - Start: ${activity.startTime}');
      print('  - HR data points: ${activity.heartRateData.length}');
      print('  - Power data points: ${activity.powerData.length}');
      print('  - Avg HR: ${activity.avgHeartRate} bpm');
      print('  - Avg Power: ${activity.avgPower.round()}W');

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

      print('Upload fields:');
      print('  - data_type: fit');
      print('  - trainer: 1');
      print('  - activity_type: VirtualRide');

      // Add FIT file
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        fitFilePath,
      ));

      print('Sending request to Strava...');

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final uploadId = data['id'];

        print('Upload successful! Upload ID: $uploadId');
        print('Waiting for Strava to process the activity...');

        // Wait for processing and get activity ID
        final activityId = await _waitForUpload(uploadId);

        // Clean up FIT file (non-blocking, just log errors)
        try {
          if (await fitFile.exists()) {
            await fitFile.delete();
            print('FIT file cleaned up successfully');
          }
        } catch (e) {
          print('Warning: Could not delete FIT file: $e');
          // Don't throw - upload was successful
        }

        // Return activity ID or upload ID as fallback
        final finalActivityId = activityId ?? data['activity_id']?.toString() ?? uploadId.toString();
        print('Final activity ID: $finalActivityId');
        return finalActivityId;
      } else {
        throw Exception('Upload failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('Upload error: $e');
    }
  }

  /// Wait for upload to be processed and return activity ID
  Future<String?> _waitForUpload(int uploadId) async {
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

          // Check if there's an error
          if (data['error'] != null) {
            print('Upload error from Strava: ${data['error']}');
            return null;
          }

          // Check if upload is complete and has activity_id
          if (data['activity_id'] != null) {
            final activityId = data['activity_id'].toString();
            final status = data['status'] ?? '';

            print('Upload status: $status');
            print('Activity ID found: $activityId');

            // If status is not "processing", consider it ready
            if (status != 'Your activity is still being processed.') {
              print('Upload complete! Activity ID: $activityId is ready');
              return activityId;
            }
          }
        }
      } catch (e) {
        print('Waiting for upload (attempt ${i + 1}/30): $e');
        // Continue waiting
      }
    }

    print('Upload wait timeout - Strava is still processing');
    return null; // Timeout, activity may still be processing
  }

  /// Upload photo to activity
  /// Note: Strava API v3 requires 'activity_photo' as field name
  Future<bool> uploadPhotoToActivity(String activityId, List<int> photoBytes) async {
    if (!isAuthenticated) {
      throw Exception('Not authenticated');
    }

    try {
      // Save photo to temp file
      final tempDir = Directory.systemTemp;
      final photoFile = File('${tempDir.path}/workout_graph_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await photoFile.writeAsBytes(photoBytes);

      // Create multipart request - Strava uses activity_photo field name
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$API_URL/activities/$activityId/photos'),
      );

      request.headers['Authorization'] = 'Bearer $_accessToken';

      // Add photo file with correct field name
      request.files.add(await http.MultipartFile.fromPath(
        'activity_photo',  // Strava requires this field name
        photoFile.path,
        filename: 'workout_graph.jpg',
      ));

      print('Uploading photo to activity $activityId...');

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('Photo upload response: ${response.statusCode}');
      print('Photo upload body: ${response.body}');

      // Store result before cleanup
      final bool uploadSuccess = (response.statusCode == 201 || response.statusCode == 200);

      // Clean up temp file (non-blocking)
      try {
        if (await photoFile.exists()) {
          await photoFile.delete();
          print('Temp photo file cleaned up');
        }
      } catch (e) {
        print('Warning: Could not delete temp photo file: $e');
        // Don't affect upload result
      }

      if (uploadSuccess) {
        print('Photo uploaded successfully!');
        return true;
      } else {
        print('Photo upload failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Photo upload error: $e');
      return false;
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
