import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  Future<String> fetchToken({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/auth/authenticate');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        if (responseBody['access_token'] != null) {
          return responseBody['access_token'];
        } else {
          throw Exception('Access token not found in response');
        }
      } else {
        // Attempt to parse error message from response if available
        String errorMessage =
            'Authentication failed with status code ${response.statusCode}';
        try {
          final errorBody = jsonDecode(response.body);
          if (errorBody['message'] != null) {
            errorMessage += ': ${errorBody['message']}';
          }
        } catch (_) {
          // Ignore if response body is not valid JSON or doesn't contain 'message'
          errorMessage += '\nResponse body: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } on http.ClientException catch (e) {
      // Handle network-related errors
      throw Exception('Network error during authentication: ${e.message}');
    } catch (e) {
      // Handle other errors (e.g., JSON parsing)
      throw Exception('An unexpected error occurred during authentication: $e');
    }
  }
}
