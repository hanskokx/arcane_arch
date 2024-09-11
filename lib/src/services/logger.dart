import "dart:async";
import "dart:io" show Platform;

import "package:arcane_framework/arcane_framework.dart";
import "package:arcane_helper_utils/arcane_helper_utils.dart";
import "package:flutter/foundation.dart";

export "package:logger/logger.dart" show Level;

/// A singleton class that manages logging to one or more logging interfaces
/// with optional metadata.
///
/// The `ArcaneLogger` provides a centralized way to log messages across
/// different parts of an application. It supports multiple logging interfaces,
/// metadata, and platform-specific error handling. It integrates with
/// [AppTrackingTransparency] for tracking authorization status on fruit-shaped
/// operating systems.
class ArcaneLogger {
  ArcaneLogger._internal();

  static final ArcaneLogger _instance = ArcaneLogger._internal();

  /// Provides access to the singleton instance of `ArcaneLogger`.
  static ArcaneLogger get I => _instance;

  final List<LoggingInterface> _interfaces = [];

  /// A list of registered logging interfaces.
  List<LoggingInterface> get interfaces => I._interfaces;

  final Map<String, String> _additionalMetadata = {};

  /// Additional metadata that is included in all logs.
  Map<String, String> get additionalMetadata => I._additionalMetadata;

  TrackingStatus _trackingStatus = TrackingStatus.notDetermined;

  /// The tracking authorization status for the current platform.
  TrackingStatus get trackingStatus => I._trackingStatus;

  bool _initialized = false;

  /// Whether the logger has been initialized.
  bool get initialized => I._initialized;

  /// Marks the logger as mocked for testing purposes.
  ///
  /// If the logger is mocked, platform-specific features (such as tracking
  /// status) will not be initialized.
  @visibleForTesting
  void setMocked() => _mocked = true;
  bool _mocked = false;

  /// Initializes the logger.
  ///
  /// Sets up error handling for both Flutter and platform-specific errors.
  /// Also, retrieves the tracking authorization status if running on iOS or
  /// macOS.
  Future<void> _init() async {
    if (_mocked) return;

    additionalMetadata.clear();

    // Handles unhandled Flutter errors by logging them.
    FlutterError.onError = (errorDetails) {
      log(
        "UNHANDLED FLUTTER ERROR",
        level: Level.error,
        module: errorDetails.library,
        stackTrace: errorDetails.stack,
        metadata: {
          "details": errorDetails.exceptionAsString(),
        },
      );
    };

    // Handles unhandled platform-specific errors by logging them.
    PlatformDispatcher.instance.onError = (error, stack) {
      log(
        "UNHANDLED PLATFORM ERROR",
        level: Level.error,
        stackTrace: stack,
        metadata: {
          "details": error.toString(),
        },
      );
      return true;
    };

    I._trackingStatus =
        await AppTrackingTransparency.trackingAuthorizationStatus;

    if (!(Platform.isIOS || Platform.isMacOS)) {
      I._trackingStatus = TrackingStatus.authorized;
    }

    I._initialized = true;
  }

  /// Logs a message with additional contextual information, optionally including
  /// metadata, stack trace, and log level.
  ///
  /// This method provides a structured way to log messages within an application,
  /// including relevant details such as module, method, and metadata. It supports
  /// different log levels.
  ///
  /// **Parameters:**
  ///
  /// - `message` (String):
  ///   The main log message to be recorded. This is the primary content that
  ///   describes the event or state being logged.
  ///
  /// - `module` (String?, _optional_):
  ///   The name of the module where the log originates. If not provided, it will
  ///   be inferred from the current stack trace. This helps in categorizing logs
  ///   by different parts of the application.
  ///
  /// - `method` (String?, _optional_):
  ///   The name of the method where the log originates. If not provided, it will
  ///   be inferred from the current stack trace. This adds context to the log by
  ///   identifying the specific method generating the log.
  ///
  /// - `level` (Level, _optional_):
  ///   The severity level of the log. Defaults to `Level.debug`. This determines
  ///   the importance of the log and influences how it is handled and displayed.
  ///
  /// - `stackTrace` (StackTrace?, _optional_):
  ///   The stack trace associated with the log event. Useful for error and
  ///   warning logs to trace the execution path leading to the log event.
  ///
  /// - `metadata` (Map<String, String>?, _optional_):
  ///   Additional key-value pairs providing extra context for the log. Commonly
  ///   used for custom information that can aid in diagnosing issues or
  ///   understanding the log in context. If not provided, an empty map is used.
  ///
  /// **Details:**
  ///
  /// The `log` method constructs a timestamp and extracts information from the
  /// current stack trace to automatically determine the `module` and `method`
  /// if they are not explicitly provided. This process can sometimes lead to\
  /// inaccurate results, thus the optional parameters which have been provided.
  /// The metadata map is populated with default values, including `timestamp`,
  /// `module`, `method`, and `filenameAndLineNumber`.
  ///
  /// The log message and associated metadata is sent to any and all registered
  /// logging interfaces.
  ///
  /// **Usage:**
  ///
  /// ```dart
  /// ArcaneLogger.log(
  ///   "An example log message",
  ///   level: Level.info,
  ///   module: "MyStateManagement",
  ///   method: "onProcessEvent",
  ///   metadata: {
  ///     "example": "value",
  ///   },
  /// );
  /// ```
  ///
  void log(
    String message, {
    String? module,
    String? method,
    Level level = Level.debug,
    StackTrace? stackTrace,
    Map<String, String>? metadata,
  }) {
    if (I._mocked) return;

    if (!I._initialized) {
      throw Exception("ArcaneLogger has not yet been initialized.");
    }

    metadata ??= <String, String>{};

    final String now = DateTime.now().toIso8601String();
    metadata.putIfAbsent("timestamp", () => now);

    try {
      final List<String> parts = StackTrace.current
          .toString()
          .split("\n")[2]
          .split(RegExp("#2"))[1]
          .trimLeft()
          .split(".");

      module ??= parts.first.replaceFirst("new ", "");
      method ??= parts[1].split(" ").first;

      final String line = parts.last.substring(5).replaceAll(")", "");
      final String file = parts[1].split(" ").last.replaceAll("(package:", "");
      final String fileAndLine = "$file:$line";

      metadata.putIfAbsent("module", () => module!);
      metadata.putIfAbsent("method", () => method!);
      metadata.putIfAbsent("filenameAndLineNumber", () => fileAndLine);
    } catch (_) {}

    metadata.addAll(additionalMetadata);

    // Send logs to registered interface(s)
    for (final LoggingInterface i in I._interfaces) {
      i.log(
        message,
        level: level,
        metadata: metadata,
        stackTrace: stackTrace,
      );
    }
  }

  /// Registers a [LoggingInterface] with the [ArcaneLogger]. If the current
  /// operating system is not a fruit-shaped OS, it will automatically be
  /// initalized. Otherwise, app tracking permissions must first be checked for
  /// and (optionally) granted before the interface is automatically initialized.
  ///
  /// Once your [LoggingInterface] has been registered and initialized, logs
  /// will automatically be sent to the interface.
  Future<ArcaneLogger> registerInterfaces(
    List<LoggingInterface> interfaces,
  ) async {
    if (!initialized) await _init();

    for (final LoggingInterface i in interfaces) {
      I._interfaces.add(i);
      if (i is ArcaneDebugConsole) {
        await I._interfaces.firstWhere((x) => x == i).init();
      }
    }

    return I;
  }

  /// Initializes all registered [LoggingInterface]s by calling their
  /// [LoggingInterface.init] methods.
  Future<ArcaneLogger> initializeInterfaces() async {
    assert(
      I._interfaces.isNotEmpty,
      "No logging interfaces have been registered.",
    );

    if (!I._initialized) await _init();
    for (final LoggingInterface i in I._interfaces) {
      if (!i.initialized) await i.init();
    }

    return I;
  }

  /// This will ask the user to approve app tracking permissions on
  /// fruit-shaped operating systems. An optional `trackingDialog` method can be
  /// passed in, which could be used to display a message to users that they're
  /// about to be asked for tracking permissions. The `trackingDialog` method
  /// will only be run if the tracking status is `notDetermined`.
  ///
  /// If app tracking has been allowed, all registered [LoggingInterface]s will
  /// be initialized.
  Future<void> initalizeAppTracking({
    Future<void>? trackingDialog,
  }) async {
    if (I._mocked) return;
    if (!I._initialized) await _init();
    if (I._trackingStatus == TrackingStatus.authorized) {
      await initializeInterfaces();
      return;
    }

    // If the system can show an authorization request dialog
    if (I._trackingStatus == TrackingStatus.notDetermined) {
      // Show a custom explainer dialog before the system dialog
      if (trackingDialog != null) await trackingDialog;
      // Wait for dialog popping animation
      await Future.delayed(const Duration(milliseconds: 200));
      // Request system's tracking authorization dialog
      await AppTrackingTransparency.requestTrackingAuthorization();
    }

    I._trackingStatus =
        await AppTrackingTransparency.trackingAuthorizationStatus;

    if (I._trackingStatus == TrackingStatus.authorized) {
      await initializeInterfaces();
    }
  }

  /// Removes a specific key from the persistent metadata.
  ArcaneLogger removePersistentMetadata(String key) {
    final bool keyPresent = additionalMetadata.containsKey(key);

    if (keyPresent) {
      additionalMetadata.removeWhere((k, v) => k == key);
    }

    return I;
  }

  /// Adds or updates persistent metadata.
  ///
  /// This metadata will be included in all future log messages.
  ArcaneLogger addPersistentMetadata(Map<String, String?> input) {
    for (final entry in input.entries) {
      final String key = entry.key;
      final String? value = entry.value;

      final bool keyPresent = _additionalMetadata.containsKey(key);

      if (keyPresent && value.isNullOrEmpty) {
        _additionalMetadata.removeWhere((k, v) => k == key);
        return I;
      }

      if (value == null) return I;

      _additionalMetadata.removeWhere((k, v) => k == key);
      _additionalMetadata.putIfAbsent(key, () => value);
    }

    return I;
  }

  /// Clears all persistent metadata.
  void clearPersistentMetadata() => _additionalMetadata.clear();
}

/// Represents a logging interface that can log messages to different destinations.
///
/// Concrete implementations of this class should override the [log] method to provide
/// platform-specific logging behavior.
abstract class LoggingInterface {
  LoggingInterface._internal();
  static late final LoggingInterface _instance;

  /// Provides access to the singleton instance of the `LoggingInterface`. This
  /// ensures that the logging interface, once configured, remains so.
  static LoggingInterface get I => _instance;

  final bool _initialized = false;

  /// Whether the logging interface has been initialized.
  bool get initialized => I._initialized;

  /// Initializes the logging interface.
  ///
  /// If any configuration needs to be performed on the logging interface prior
  /// to use, this is where it should be done.
  /// This method should, at a minimum, set `I._initialized = true`.
  Future<LoggingInterface?> init();

  /// This method is called by the `ArcaneLogger` when a log message is
  /// received. See `ArcaneLogger.log` for further details on how logging
  /// works and what options are available.
  void log(
    String message, {
    Map<String, dynamic>? metadata,
    Level? level,
    StackTrace? stackTrace,
  });
}

/// A special logging interface which specifically targets the local debug
/// console. This `LoggingInterface` differs in that it is immediately
/// initialized when it is registered with the `ArcaneLogger`.
abstract class ArcaneDebugConsole implements LoggingInterface {}
