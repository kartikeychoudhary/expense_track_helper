import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart'; // Import SmsMessage
import 'package:multi_dropdown/multiselect_dropdown.dart'; // Import multi_dropdown
import '../services/storage_service.dart'; // Import StorageService
import '../services/auth_service.dart'; // Import AuthService
import '../services/sms_service.dart'; // Import SmsService
import '../services/api_service.dart'; // Import ApiService
import 'package:intl/intl.dart'; // Import intl

// Define Time Filter Enum
enum SmsTimeFilter { today, yesterday, last7Days, thisMonth, lastMonth, all }

extension SmsTimeFilterExtension on SmsTimeFilter {
  String get displayName {
    switch (this) {
      case SmsTimeFilter.today:
        return 'Today';
      case SmsTimeFilter.yesterday:
        return 'Yesterday';
      case SmsTimeFilter.last7Days:
        return 'Last 7 Days';
      case SmsTimeFilter.thisMonth:
        return 'This Month';
      case SmsTimeFilter.lastMonth:
        return 'Last Month';
      case SmsTimeFilter.all:
        return 'All Time';
    }
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Controllers for the text fields
  final _urlController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // final _sendersController = TextEditingController(); // REMOVED

  final _storageService = StorageService(); // Instantiate StorageService
  final _authService = AuthService(); // Instantiate AuthService
  final _smsService = SmsService(); // Instantiate SmsService
  final _apiService = ApiService(); // Instantiate ApiService
  bool _isLoadingConfig = false; // Renamed for clarity
  bool _isFetchingToken = false; // Added for token fetch state
  bool _isFetchingSms = false; // Added for SMS fetch state
  List<SmsMessage> _smsList = []; // List to hold fetched SMS
  Set<String> _sentSmsIds = {}; // Set to hold IDs of sent SMS
  Set<String> _sendingSmsIds = {}; // Track IDs of SMS currently being sent
  bool _isConfigExpanded = true; // State for ExpansionTile
  bool _hasAccessToken = false; // State for token status
  // New state for dropdown
  List<ValueItem<String>> _allPossibleSenders = [];
  List<ValueItem<String>> _selectedSenders = [];
  List<String> _initialSelectedSenderStrings =
      []; // Store initially loaded strings
  final MultiSelectController<String> _dropdownController =
      MultiSelectController(); // Controller for dropdown
  bool _isFetchingAllSenders = false;
  SmsTimeFilter _selectedTimeFilter = SmsTimeFilter.today; // Default to Today

  final DateFormat smsDateFormatter = DateFormat(
    'dd MMM yy, HH:mm',
  ); // Define formatter

  @override
  void initState() {
    super.initState();
    _loadInitialData(); // Load initial data (sent IDs, config)
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoadingConfig = true);
    try {
      _sentSmsIds = await _storageService.loadSentSmsIds();
      // Load config first to get initial selected strings
      await _loadConfiguration();
      // Fetch all senders AND apply initial selection
      await _fetchAllSendersFromDevice();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading initial data: $e')),
        );
      }
      if (mounted)
        setState(
          () => _isLoadingConfig = false,
        ); // Ensure loading stops on error
    }
    // Loading state should be false now, handled by _fetchAllSenders or catch block
  }

  Future<void> _loadConfiguration() async {
    if (!mounted) return;
    // Don't manage loading indicator here; handled by _loadInitialData/_fetchAllSenders
    try {
      await _checkTokenStatus();
      final config = await _storageService.loadConfiguration();
      _urlController.text = config['url'] ?? '';
      _emailController.text = config['email'] ?? '';
      _passwordController.text = config['password'] ?? '';
      // Load and store the initial strings, don't set _selectedSenders yet
      _initialSelectedSenderStrings = config['senders'] as List<String>? ?? [];

      // Don't trigger SMS fetch here, wait until senders are confirmed selected after _fetchAllSenders
      // if (_selectedSenders.isNotEmpty) { _fetchSmsMessages(); }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading configuration: $e')),
        );
      }
      // Rethrow or handle error appropriately if needed for initial load sequence
    }
    // No finally block needed for loading state here
  }

  Future<void> _saveConfiguration() async {
    setState(() => _isLoadingConfig = true);
    try {
      // Get selected sender strings from the state
      final List<String> selectedSenderStrings =
          _selectedSenders.map((item) => item.value!).toList();

      await _storageService.saveConfiguration(
        url: _urlController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        selectedSenders: selectedSenderStrings, // Save the list of strings
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration saved successfully!')),
        );
        // Trigger SMS fetch if senders are selected
        if (_selectedSenders.isNotEmpty) {
          _fetchSmsMessages();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving configuration: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingConfig = false);
      }
    }
  }

  Future<void> _fetchToken() async {
    final url = _urlController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (url.isEmpty || email.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('URL, Email, and Password cannot be empty.'),
          ),
        );
      }
      return;
    }

    setState(() => _isFetchingToken = true);
    try {
      final token = await _authService.fetchToken(
        baseUrl: url,
        email: email,
        password: password,
      );
      await _storageService.saveAccessToken(token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Token fetched and saved successfully!'),
          ),
        );
        setState(() => _hasAccessToken = true); // Update state on success
      }
    } catch (e) {
      if (mounted) {
        await _storageService.clearAccessToken();
        setState(() => _hasAccessToken = false); // Update state on failure
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching token: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingToken = false);
      }
    }
  }

  Future<void> _fetchAllSendersFromDevice() async {
    if (!mounted) return;
    // Ensure loading state is true if called independently (refresh)
    if (!_isLoadingConfig) setState(() => _isLoadingConfig = true);
    setState(() => _isFetchingAllSenders = true);

    List<ValueItem<String>> newlyFetchedSenders = [];
    try {
      final List<String> senders = await _smsService.getAllSenders();
      newlyFetchedSenders =
          senders.map((s) => ValueItem(label: s, value: s)).toList();

      if (mounted) {
        // Determine initial selection based on loaded strings and *newly fetched* options
        final validInitialSelections =
            newlyFetchedSenders
                .where(
                  (item) => _initialSelectedSenderStrings.contains(item.value),
                )
                .toList();

        setState(() {
          _allPossibleSenders = newlyFetchedSenders;
          // Set the state variable for selected items *now*
          _selectedSenders = validInitialSelections;
        });

        // Trigger initial SMS fetch *if* senders were actually selected
        if (_selectedSenders.isNotEmpty) {
          _fetchSmsMessages();
        }

        // Show snackbar immediately after state update
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Refreshed sender list (${senders.length} unique found).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error fetching senders: $e')));
      }
    } finally {
      if (mounted) {
        // Always set both flags to false when done fetching senders
        setState(() {
          _isFetchingAllSenders = false;
          _isLoadingConfig = false; // Final step for loading
        });
      }
    }
  }

  Future<void> _fetchSmsMessages() async {
    // Get sender list from state
    final List<String> sendersList =
        _selectedSenders.map((item) => item.value!).toList();

    if (sendersList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sender list is empty. Cannot fetch SMS.'),
          ),
        );
      }
      return; // Stop if no senders
    }

    setState(() => _isFetchingSms = true);
    _smsList.clear(); // Clear list before fetching all

    try {
      // 1. Check/Request Permission
      final permissionGranted = await _smsService.requestSmsPermission();
      if (!permissionGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('SMS permission denied. Cannot fetch messages.'),
            ),
          );
        }
        return; // Stop if permission denied
      }

      // Fetch ALL messages for selected senders first
      final fetchedMessages = await _smsService.fetchSmsMessages(
        senders: sendersList,
      );

      // Calculate start date based on filter
      final DateTime now = DateTime.now();
      DateTime? filterStartDate;
      switch (_selectedTimeFilter) {
        case SmsTimeFilter.today:
          filterStartDate = DateTime(now.year, now.month, now.day);
          break;
        case SmsTimeFilter.yesterday:
          final yesterday = now.subtract(const Duration(days: 1));
          filterStartDate = DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
          );
          break;
        case SmsTimeFilter.last7Days:
          filterStartDate = now.subtract(const Duration(days: 7));
          // Optional: Start from beginning of the 7th day ago?
          // filterStartDate = DateTime(filterStartDate.year, filterStartDate.month, filterStartDate.day);
          break;
        case SmsTimeFilter.thisMonth:
          filterStartDate = DateTime(now.year, now.month, 1);
          break;
        case SmsTimeFilter.lastMonth:
          final firstDayOfCurrentMonth = DateTime(now.year, now.month, 1);
          final lastDayOfLastMonth = firstDayOfCurrentMonth.subtract(
            const Duration(days: 1),
          );
          filterStartDate = DateTime(
            lastDayOfLastMonth.year,
            lastDayOfLastMonth.month,
            1,
          );
          break;
        case SmsTimeFilter.all:
          filterStartDate = null; // No date filter
          break;
      }
      // For 'yesterday', we also need an end date (start of today)
      DateTime? filterEndDate;
      if (_selectedTimeFilter == SmsTimeFilter.yesterday) {
        filterEndDate = DateTime(now.year, now.month, now.day);
      }
      if (_selectedTimeFilter == SmsTimeFilter.lastMonth) {
        filterEndDate = DateTime(
          now.year,
          now.month,
          1,
        ); // End of last month is start of this month
      }

      // Apply Time Filter first
      List<SmsMessage> timeFilteredMessages = fetchedMessages;
      if (filterStartDate != null) {
        timeFilteredMessages =
            fetchedMessages.where((msg) {
              if (msg.date == null)
                return false; // Exclude messages without a date
              bool afterStart = msg.date!.isAfter(filterStartDate!);
              bool beforeEnd =
                  filterEndDate == null || msg.date!.isBefore(filterEndDate);
              // Special case for today/yesterday: include messages *on* the start date
              if ((_selectedTimeFilter == SmsTimeFilter.today ||
                      _selectedTimeFilter == SmsTimeFilter.yesterday) &&
                  msg.date!.year == filterStartDate.year &&
                  msg.date!.month == filterStartDate.month &&
                  msg.date!.day == filterStartDate.day) {
                return beforeEnd; // If on start date, just check end date
              }
              return afterStart && beforeEnd;
            }).toList();
      }

      // Filter out already sent messages
      final unsentMessages =
          timeFilteredMessages
              .where(
                (msg) =>
                    msg.id != null && !_sentSmsIds.contains(msg.id.toString()),
              )
              .toList();

      // Update state by REPLACING the list
      if (mounted) {
        setState(() {
          _smsList = unsentMessages;
          // Sort by date descending
          _smsList.sort(
            (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
          );
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Fetched ${_smsList.length} unsent SMS messages (${_selectedTimeFilter.displayName}).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error fetching SMS: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingSms = false);
      }
    }
  }

  Future<void> _sendSms(SmsMessage sms) async {
    final String smsId =
        sms.id?.toString() ?? 'no_id_${sms.date?.millisecondsSinceEpoch}';
    if (sms.body == null || sms.body!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cannot send empty SMS.')));
      return;
    }

    setState(() {
      _sendingSmsIds.add(smsId);
    });

    try {
      // Get necessary data from storage
      final baseUrl = await _storageService.getUrl();
      final accessToken = await _storageService.loadAccessToken();

      if (baseUrl == null || baseUrl.isEmpty) {
        throw Exception('Backend URL is not configured.');
      }
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception(
          'Access token is not available. Please fetch token first.',
        );
      }
      var formattedDate;
      try {
        formattedDate = 'SMS Received at: ${smsDateFormatter.format(sms.date!)}';
      } catch (e) {
        formattedDate = ''; // Handle potential formatting errors
      }

      // Call API service
      await _apiService.sendSmsData(
        baseUrl: baseUrl,
        accessToken: accessToken,
        smsBody: sms.body!,
        formattedDate: formattedDate,
      );

      // On Success:
      // 1. Add to sent IDs set
      _sentSmsIds.add(smsId);
      // 2. Persist the updated sent IDs
      await _storageService.saveSentSmsIds(_sentSmsIds);
      // 3. Remove from the list in UI
      if (mounted) {
        setState(() {
          _smsList.removeWhere(
            (item) =>
                (item.id?.toString() ??
                    'no_id_${item.date?.millisecondsSinceEpoch}') ==
                smsId,
          );
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('SMS sent successfully!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending SMS: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingSmsIds.remove(smsId);
        });
      }
    }
  }

  Future<void> _checkTokenStatus() async {
    final token = await _storageService.loadAccessToken();
    if (mounted) {
      setState(() {
        _hasAccessToken = token != null && token.isNotEmpty;
      });
    }
  }

  @override
  void dispose() {
    // Dispose controllers when the widget is removed from the widget tree
    _urlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    // _sendersController.dispose(); // REMOVED
    _dropdownController.dispose(); // Dispose dropdown controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isInitialLoading = _isLoadingConfig && _smsList.isEmpty;
    final theme = Theme.of(context); // Get theme data
    final colorScheme = theme.colorScheme; // Get color scheme

    // Create a key based on the options list to force rebuild when it changes
    final dropdownKey = ValueKey(_allPossibleSenders);

    return Scaffold(
      appBar: AppBar(
        title: const Text('wheremybuckgoes sms helper'),
        backgroundColor:
            colorScheme.inversePrimary, // Add background color to AppBar
      ),
      body:
          isInitialLoading
              ? const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: "Loading configuration...",
                ),
              )
              : Padding(
                padding: const EdgeInsets.all(
                  16.0,
                ), // Outer padding for the whole body content
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- Configuration Section (Collapsible) ---
                    ExpansionTile(
                      title: const Text(
                        'Backend Configuration',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      initiallyExpanded: _isConfigExpanded,
                      onExpansionChanged: (bool expanded) {
                        setState(() {
                          _isConfigExpanded = expanded;
                        });
                      },
                      childrenPadding: const EdgeInsets.symmetric(
                        horizontal: 8.0, // Reduced horizontal padding
                        vertical:
                            0, // Remove vertical padding, let Card handle it
                      ), // Padding inside tile
                      children: [
                        // Wrap content in a Card for better visual separation
                        Card(
                          margin: const EdgeInsets.symmetric(
                            vertical: 8.0,
                          ), // Add margin around the card
                          elevation: 1, // Subtle elevation
                          child: Padding(
                            padding: const EdgeInsets.all(
                              16.0,
                            ), // Padding inside the card
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _urlController,
                                  decoration: const InputDecoration(
                                    labelText: 'Backend URL',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.url,
                                  enabled: !_isFetchingToken && !_isFetchingSms,
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _emailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  enabled: !_isFetchingToken && !_isFetchingSms,
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _passwordController,
                                  decoration: const InputDecoration(
                                    labelText: 'Password',
                                    border: OutlineInputBorder(),
                                  ),
                                  obscureText: true,
                                  enabled: !_isFetchingToken && !_isFetchingSms,
                                ),
                                const SizedBox(height: 15),
                                // --- Token Status ---
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 5.0,
                                  ), // Add some bottom spacing
                                  child: Text(
                                    _hasAccessToken
                                        ? 'Access Token: Present'
                                        : 'Access Token: Not Found',
                                    style: TextStyle(
                                      color:
                                          _hasAccessToken
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign:
                                        TextAlign.center, // Center the text
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // --- Senders Dropdown Section ---
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Expanded(
                                      flex: 8, // Give dropdown more space
                                      child: Text(
                                        'SMS Senders',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2, // Give button less space
                                      child: IconButton(
                                        tooltip:
                                            'Refresh sender list from device',
                                        icon:
                                            _isFetchingAllSenders
                                                ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                                : const Icon(Icons.refresh),
                                        onPressed:
                                            _isLoadingConfig ||
                                                    _isFetchingAllSenders ||
                                                    _isFetchingSms ||
                                                    _isFetchingToken
                                                ? null // Disable if any loading is happening
                                                : _fetchAllSendersFromDevice,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                MultiSelectDropDown<String>(
                                  key: dropdownKey,
                                  controller: _dropdownController,
                                  onOptionSelected: (
                                    List<ValueItem<String>> selectedOptions,
                                  ) {
                                    if (mounted) {
                                      setState(() {
                                        _selectedSenders = selectedOptions;
                                      });
                                    }
                                  },
                                  options: _allPossibleSenders,
                                  selectedOptions: _selectedSenders,
                                  disabledOptions:
                                      _isFetchingAllSenders
                                          ? _allPossibleSenders
                                          : [],
                                  selectionType: SelectionType.multi,
                                  chipConfig: const ChipConfig(
                                    wrapType: WrapType.wrap,
                                    backgroundColor: Colors.blueAccent,
                                  ),
                                  dropdownHeight: 300,
                                  optionTextStyle: const TextStyle(
                                    fontSize: 16,
                                  ),
                                  selectedOptionIcon: const Icon(
                                    Icons.check_circle,
                                  ),
                                  selectedOptionBackgroundColor:
                                      Colors.grey.shade300,
                                  searchEnabled: true,
                                  hint: 'Select Senders',
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.tonalIcon(
                                        // Use default shape or specify slight rounding if desired
                                        // style: FilledButton.styleFrom(
                                        //   shape: RoundedRectangleBorder(
                                        //     borderRadius: BorderRadius.circular(8.0), // Example rounding
                                        //   ),
                                        // ),
                                        onPressed:
                                            _isLoadingConfig ||
                                                    _isFetchingToken ||
                                                    _isFetchingSms
                                                ? null
                                                : _saveConfiguration,
                                        icon:
                                            _isLoadingConfig
                                                ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                                : const Icon(Icons.save),
                                        label: const Text('Save'),
                                      ),
                                    ),
                                    const SizedBox(
                                      width: 8,
                                    ), // Spacing between buttons
                                    Expanded(
                                      child: FilledButton.tonalIcon(
                                        // Use default shape
                                        // style: FilledButton.styleFrom(
                                        //   shape: RoundedRectangleBorder(
                                        //     borderRadius: BorderRadius.circular(8.0), // Example rounding
                                        //   ),
                                        // ),
                                        onPressed:
                                            _isLoadingConfig ||
                                                    _isFetchingToken ||
                                                    _isFetchingSms
                                                ? null
                                                : _fetchToken,
                                        icon:
                                            _isFetchingToken
                                                ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                                : const Icon(Icons.token),
                                        label: const Text('Fetch Token'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Separator moved outside ExpansionTile if needed, or handled by tile border
                    // const Divider(height: 30, thickness: 1), // Divider might be redundant now
                    const SizedBox(
                      height: 16,
                    ), // Add space after ExpansionTile -> Configuration Card
                    // --- SMS Section Title ---
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0, // Add horizontal padding to title
                      ),
                      child: Text(
                        'Unsent SMS Messages (${_selectedTimeFilter.displayName})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ), // Space between title and controls
                    // Row 2: Filter Dropdown and Fetch Button (Wrapped in Card)
                    Card(
                      margin: const EdgeInsets.only(
                        bottom: 10.0,
                      ), // Margin below the card
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 8.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Time Filter Dropdown
                            SizedBox(
                              width: 150, // Give dropdown a fixed width
                              child: DropdownButton<SmsTimeFilter>(
                                isExpanded: true, // Allow dropdown to expand
                                value: _selectedTimeFilter,
                                // Show loading indicator if fetching SMS
                                icon:
                                    _isFetchingSms
                                        ? const SizedBox(
                                          width: 12, // Smaller indicator
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Icon(Icons.arrow_drop_down),
                                underline: Container(
                                  height: 1,
                                  color: Colors.grey, // Or your theme color
                                ),
                                onChanged:
                                    _isFetchingSms ||
                                            _isLoadingConfig ||
                                            _isFetchingAllSenders ||
                                            _isFetchingToken
                                        ? null // Disable dropdown during fetch
                                        : (SmsTimeFilter? newValue) {
                                          if (newValue != null) {
                                            setState(() {
                                              _selectedTimeFilter = newValue;
                                            });
                                            _fetchSmsMessages(); // Refetch with new filter
                                          }
                                        },
                                items:
                                    SmsTimeFilter.values.map<
                                      DropdownMenuItem<SmsTimeFilter>
                                    >((SmsTimeFilter value) {
                                      return DropdownMenuItem<SmsTimeFilter>(
                                        value: value,
                                        child: Text(
                                          value.displayName,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                              ),
                            ),
                            const Spacer(), // Pushes fetch button to the right
                            // Fetch SMS Button
                            ElevatedButton.icon(
                              // Disable button if loading config, fetching token, fetching SMS, or fetching all senders
                              onPressed:
                                  _isLoadingConfig ||
                                          _isFetchingToken ||
                                          _isFetchingSms || // Disable if fetching SMS
                                          _isFetchingAllSenders || // Disable if fetching senders
                                          _selectedSenders
                                              .isEmpty // Disable if no senders selected
                                      ? null
                                      : _fetchSmsMessages,
                              icon:
                                  _isFetchingSms // Show progress only when fetching SMS specifically
                                      ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color:
                                              Colors
                                                  .white, // Color for contrast on button
                                        ),
                                      )
                                      : const Icon(
                                        Icons.cloud_download_outlined,
                                      ), // Changed icon
                              label: const Text('Fetch SMS'), // Clearer label
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child:
                          _isFetchingSms && _smsList.isEmpty
                              ? const Center(
                                child: CircularProgressIndicator(
                                  semanticsLabel: "Fetching SMS...",
                                ),
                              )
                              : _smsList.isEmpty
                              ? const Center(
                                child: Text(
                                  'No new SMS messages found from configured senders.',
                                ),
                              )
                              : ListView.builder(
                                padding: const EdgeInsets.only(
                                  top: 4.0,
                                  bottom: 8.0,
                                ), // Add padding around the list items
                                itemCount: _smsList.length,
                                itemBuilder: (context, index) {
                                  final sms = _smsList[index];
                                  final String smsId =
                                      sms.id?.toString() ??
                                      'no_id_${sms.date?.millisecondsSinceEpoch}';
                                  final bool isSending = _sendingSmsIds
                                      .contains(smsId);
                                  final bool isAnyOperationRunning =
                                      _isLoadingConfig ||
                                      _isFetchingToken ||
                                      _isFetchingSms || // Include SMS fetch status
                                      _isFetchingAllSenders; // Include sender fetch status

                                  // Format the date
                                  String formattedDate = '';
                                  if (sms.date != null) {
                                    try {
                                      formattedDate = smsDateFormatter.format(
                                        sms.date!,
                                      );
                                    } catch (e) {
                                      formattedDate =
                                          'Invalid Date'; // Handle potential formatting errors
                                    }
                                  } else {
                                    formattedDate = 'No Date';
                                  }

                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4.0,
                                      horizontal:
                                          4.0, // Add slight horizontal margin
                                    ),
                                    elevation: 1,
                                    child: ListTile(
                                      // Use contentPadding for inner spacing
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 8.0,
                                            horizontal: 16.0,
                                          ),
                                      // Title section now uses a Column containing the Row (Sender/Date) and the Body
                                      title: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Row for Sender and Date
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .start, // Align items at the top
                                            children: [
                                              // Sender Name (takes available space)
                                              Expanded(
                                                child: Text(
                                                  sms.sender ??
                                                      sms.address ??
                                                      'Unknown Sender',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize:
                                                        15, // Slightly larger sender font
                                                  ),
                                                  overflow:
                                                      TextOverflow
                                                          .ellipsis, // Prevent overflow
                                                ),
                                              ),
                                              const SizedBox(
                                                width: 8,
                                              ), // Space between sender and date
                                              // Date (takes needed space, aligned right)
                                              Text(
                                                formattedDate,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall?.copyWith(
                                                  fontSize: 11,
                                                ), // Smaller, subtle style
                                                textAlign:
                                                    TextAlign
                                                        .right, // Ensure right alignment
                                              ),
                                            ],
                                          ),
                                          const SizedBox(
                                            height: 6,
                                          ), // Space between title row and body
                                          // SMS Body
                                          Text(
                                            sms.body ?? '(No Content)',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.copyWith(
                                              color:
                                                  Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.color, // Use a slightly dimmer color
                                            ),
                                            maxLines: 4, // Allow more lines
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                      trailing: TextButton(
                                        // style: flatRectangularButtonStyle, // Removed
                                        onPressed:
                                            isSending || isAnyOperationRunning
                                                ? null
                                                : () => _sendSms(sms),
                                        child:
                                            isSending
                                                ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                                : const Text('Send'),
                                      ),
                                      isThreeLine:
                                          false, // Ensure ListTile adjusts height correctly
                                    ),
                                  );
                                },
                              ),
                    ),
                  ],
                ),
              ),
    );
  }
}
