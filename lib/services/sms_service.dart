import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

class SmsService {
  final SmsQuery _smsQuery = SmsQuery();

  Future<bool> requestSmsPermission() async {
    var status = await Permission.sms.status;
    if (!status.isGranted) {
      status = await Permission.sms.request();
    }
    return status.isGranted;
  }

  Future<List<SmsMessage>> fetchSmsMessages({
    required List<String> senders,
    DateTime? sinceDate,
    int? count, // Optional: limit the number of messages fetched
  }) async {
    final bool permissionGranted = await requestSmsPermission();
    if (!permissionGranted) {
      throw Exception('SMS permission not granted.');
    }

    if (senders.isEmpty) {
      return []; // Return empty list if no senders are configured
    }

    // Fetch all messages first, then filter in Dart
    // Note: Filtering by address directly in the query might be possible but can be complex
    // depending on the exact format needed by the native layer. Filtering afterwards is safer.
    List<SmsMessage> allMessages = await _smsQuery.querySms(
      kinds: [SmsQueryKind.inbox], // Only fetch received messages
      count: count, // Limit fetch count if specified
    );

    // Filter messages based on senders and date
    List<SmsMessage> filteredMessages =
        allMessages.where((message) {
          // Check if sender is in the list (case-insensitive comparison)
          bool senderMatch = senders.any(
            (sender) =>
                message.sender?.toLowerCase() == sender.toLowerCase() ||
                message.address?.toLowerCase() == sender.toLowerCase(),
          );

          // Check if message date is after the specified date (if provided)
          bool dateMatch =
              sinceDate == null ||
              (message.date != null && message.date!.isAfter(sinceDate));

          return senderMatch && dateMatch;
        }).toList();

    return filteredMessages;
  }

  // Helper to parse the comma-separated sender string
  List<String> parseSendersString(String? sendersString) {
    if (sendersString == null || sendersString.trim().isEmpty) {
      return [];
    }
    return sendersString
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // New method to get all unique senders
  Future<List<String>> getAllSenders({int queryLimit = 1000}) async {
    final bool permissionGranted = await requestSmsPermission();
    if (!permissionGranted) {
      throw Exception('SMS permission not granted.');
    }

    // Query a reasonable number of recent messages to find senders
    List<SmsMessage> messages = await _smsQuery.querySms(
      kinds: [
        SmsQueryKind.inbox,
        SmsQueryKind.sent,
      ], // Check both inbox and sent
      count: queryLimit, // Limit query to avoid performance issues
    );

    // Extract unique sender addresses/names
    final Set<String> uniqueSenders = {};
    for (var message in messages) {
      final sender = message.sender ?? message.address;
      if (sender != null && sender.trim().isNotEmpty) {
        uniqueSenders.add(sender.trim());
      }
    }

    // Convert set to list and sort
    final senderList = uniqueSenders.toList();
    senderList.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return senderList;
  }
}
