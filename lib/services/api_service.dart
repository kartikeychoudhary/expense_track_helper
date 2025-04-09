import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  Future<void> sendSmsData({
    required String baseUrl,
    required String accessToken,
    required String smsBody,
  }) async {
    final url = Uri.parse('$baseUrl/api/v1/genAi');

    try {
      final response = await http.post(
        url,
        headers: { // Assuming backend expects JSON even for raw text? Check backend spec if text/plain is needed.
          'Authorization': 'Bearer $accessToken',
        },
        // The spec says send raw text, but sending as JSON string for safety unless text/plain is confirmed.
        // If backend strictly expects raw text with text/plain header, adjust headers and body accordingly.
        body: smsBody.toString(), // Sending the SMS body as a JSON string.
      );

      if (response.statusCode == 200) {
        // Successfully sent
        print('SMS data sent successfully.');
        // Handle potential response body if needed (spec doesn't define one)
        // final responseBody = jsonDecode(response.body);
        return; // Indicate success
      } else {
        // Handle backend errors
        String errorMessage =
            'Failed to send SMS data. Status: ${response.statusCode}';
        try {
          final errorBody = jsonDecode(response.body);
          if (errorBody['message'] != null) {
            errorMessage += ': ${errorBody['message']}';
          }
        } catch (_) {
          errorMessage += '\nResponse body: ${response.body}';
        }
        throw Exception(errorMessage);
      }
    } on http.ClientException catch (e) {
      // Handle network errors
      throw Exception('Network error sending SMS data: ${e.message}');
    } catch (e) {
      // Handle other errors (e.g., JSON encoding)
      throw Exception('An unexpected error occurred sending SMS data: $e');
    }
  }
}
