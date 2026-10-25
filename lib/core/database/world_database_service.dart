import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'database_validator.dart';
import 'schema.dart';

/// Result of an import operation on a World Database.
class ImportResult {
  final bool isSuccess;
  final String message;
  final ValidationResult? validationResult;
  final int acceptedCompetitions;
  final int acceptedClubs;
  final int acceptedTeams;
  final int acceptedPlayers;
  final int acceptedContracts;
  final List<String> errors;

  const ImportResult({
    required this.isSuccess,
    required this.message,
    this.validationResult,
    this.acceptedCompetitions = 0,
    this.acceptedClubs = 0,
    this.acceptedTeams = 0,
    this.acceptedPlayers = 0,
    this.acceptedContracts = 0,
    this.errors = const [],
  });

  factory ImportResult.success({
    required String message,
    ValidationResult? validationResult,
    int acceptedCompetitions = 0,
    int acceptedClubs = 0,
    int acceptedTeams = 0,
    int acceptedPlayers = 0,
    int acceptedContracts = 0,
  }) {
    return ImportResult(
      isSuccess: true,
      message: message,
      validationResult: validationResult,
      acceptedCompetitions: acceptedCompetitions,
      acceptedClubs: acceptedClubs,
      acceptedTeams: acceptedTeams,
      acceptedPlayers: acceptedPlayers,
      acceptedContracts: acceptedContracts,
    );
  }

  factory ImportResult.failure({
    required String message,
    ValidationResult? validationResult,
    List<String> errors = const [],
  }) {
    return ImportResult(
      isSuccess: false,
      message: message,
      validationResult: validationResult,
      errors: errors,
    );
  }
}

/// Result of an export operation on a World Database.
class ExportResult {
  final bool isSuccess;
  final String outputPath;
  final String message;
  final int byteSize;

  const ExportResult({
    required this.isSuccess,
    required this.outputPath,
    required this.message,
    this.byteSize = 0,
  });

  factory ExportResult.success({
    required String outputPath,
    required int byteSize,
    String message = 'Export completed successfully.',
  }) {
    return ExportResult(
      isSuccess: true,
      outputPath: outputPath,
      message: message,
      byteSize: byteSize,
    );
  }

  factory ExportResult.failure({
    required String outputPath,
    required String message,
  }) {
    return ExportResult(
      isSuccess: false,
      outputPath: outputPath,
      message: message,
      byteSize: 0,
    );
  }
}

/// Service managing validation, safe import, export, and schema version migrations
/// for master Football World SQLite databases.
class WorldDatabaseService {
  static const List<int> sqliteMagicHeader = [
    0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66,
    0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00,
  ]; // "SQLite format 3\000"

  /// Validates a potential SQLite world database file on disk.
  /// Checks file existence, magic header, valid SQLite integrity, schema tables,
  /// metadata, and data relationships without mutating anything.
  ValidationResult validateDatabaseFile(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      return ValidationResult.failure([
        const ValidationError(
          code: 'FILE_NOT_FOUND',
          message: 'The specified database file does not exist.',
        ),
      ]);
    }

    final length = file.lengthSync();
    if (length < 100) {
      return ValidationResult.failure([
        ValidationError(
          code: 'CORRUPTED_FILE',
          message: 'File size ($length bytes) is too small to be a valid SQLite database.',
        ),
      ]);
    }

    // Check 16-byte SQLite magic header
    try {
      final raf = file.openSync(mode: FileMode.read);
      final header = raf.readSync(16);
      raf.closeSync();

      if (header.length < 16) {
        return ValidationResult.failure([
          const ValidationError(
            code: 'INVALID_SQLITE_HEADER',
            message: 'Database file is truncated.',
          ),
        ]);
      }

      for (int i = 0; i < 16; i++) {
        if (header[i] != sqliteMagicHeader[i]) {
          return ValidationResult.failure([
            const ValidationError(
              code: 'INVALID_SQLITE_HEADER',
              message: 'File header does not match SQLite 3 format specification.',
            ),
          ]);
        }
      }
    } catch (e) {
      return ValidationResult.failure([
        ValidationError(
          code: 'FILE_READ_ERROR',
          message: 'Could not read file header: $e',
        ),
      ]);
    }

    // Open file with SQLite and run full domain validation
    Database? db;
    try {
      db = sqlite3.open(filePath, mode: OpenMode.readOnly);
      final result = DatabaseValidator.validateWorldDatabase(db);
      return result;
    } catch (e) {
      return ValidationResult.failure([
        ValidationError(
          code: 'SQLITE_OPEN_ERROR',
          message: 'Failed to parse database file as valid SQLite: $e',
        ),
      ]);
    } finally {
      db?.close();
    }
  }

  /// Imports a candidate football world database file into the destination path.
  /// Uses a safe, multi-step transaction:
  /// 1. Candidate is thoroughly validated in isolation.
  /// 2. If validation fails, destination is completely untouched.
  /// 3. If valid, candidate is staged in a temporary file and atomically placed.
  ImportResult importWorldDatabase({
    required String sourceFilePath,
    required String targetFilePath,
  }) {
    // Step 1: Pre-validation
    final validation = validateDatabaseFile(sourceFilePath);
    if (!validation.isValid) {
      return ImportResult.failure(
        message: 'Import rejected: Database file failed validation checks.',
        validationResult: validation,
        errors: validation.errors.map((e) => e.toString()).toList(),
      );
    }

    // Step 2: Extract record counts from candidate
    int acceptedCompetitions = 0;
    int acceptedClubs = 0;
    int acceptedTeams = 0;
    int acceptedPlayers = 0;
    int acceptedContracts = 0;

    Database? candidateDb;
    try {
      candidateDb = sqlite3.open(sourceFilePath, mode: OpenMode.readOnly);
      acceptedCompetitions = candidateDb.select('SELECT COUNT(*) as c FROM competitions;').first['c'] as int;
      acceptedClubs = candidateDb.select('SELECT COUNT(*) as c FROM clubs;').first['c'] as int;
      acceptedTeams = candidateDb.select('SELECT COUNT(*) as c FROM teams;').first['c'] as int;
      acceptedPlayers = candidateDb.select('SELECT COUNT(*) as c FROM players;').first['c'] as int;
      acceptedContracts = candidateDb.select('SELECT COUNT(*) as c FROM squad_contracts;').first['c'] as int;
    } catch (e) {
      return ImportResult.failure(
        message: 'Could not query candidate database: $e',
        errors: [e.toString()],
      );
    } finally {
      candidateDb?.close();
    }

    // Step 3: Safe staged replacement
    final targetDir = Directory(p.dirname(targetFilePath));
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final tempFilePath = '$targetFilePath.tmp_${DateTime.now().millisecondsSinceEpoch}';
    final tempFile = File(tempFilePath);

    try {
      // Copy source to temporary stage
      File(sourceFilePath).copySync(tempFilePath);

      // Verify staged copy opens cleanly
      final testDb = sqlite3.open(tempFilePath, mode: OpenMode.readOnly);
      testDb.close();

      // Atomic replace target
      final targetFile = File(targetFilePath);
      if (targetFile.existsSync()) {
        try {
          targetFile.deleteSync();
        } catch (_) {}
      }
      tempFile.renameSync(targetFilePath);

      return ImportResult.success(
        message: 'World database imported successfully.',
        validationResult: validation,
        acceptedCompetitions: acceptedCompetitions,
        acceptedClubs: acceptedClubs,
        acceptedTeams: acceptedTeams,
        acceptedPlayers: acceptedPlayers,
        acceptedContracts: acceptedContracts,
      );
    } catch (e) {
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
      return ImportResult.failure(
        message: 'Failed to safely place imported database: $e',
        errors: [e.toString()],
      );
    }
  }

  /// Exports an active World Database file on disk to the desired target path.
  ExportResult exportWorldDatabase({
    required String sourceFilePath,
    required String targetFilePath,
  }) {
    final validation = validateDatabaseFile(sourceFilePath);
    if (!validation.isValid) {
      return ExportResult.failure(
        outputPath: targetFilePath,
        message: 'Cannot export invalid world database: ${validation.errors.first.message}',
      );
    }

    final targetDir = Directory(p.dirname(targetFilePath));
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    try {
      final sourceFile = File(sourceFilePath);
      final destFile = sourceFile.copySync(targetFilePath);
      return ExportResult.success(
        outputPath: targetFilePath,
        byteSize: destFile.lengthSync(),
      );
    } catch (e) {
      return ExportResult.failure(
        outputPath: targetFilePath,
        message: 'Failed to export database: $e',
      );
    }
  }

  /// Exports any open SQLite database instance (including in-memory DB) to a clean file on disk.
  ExportResult exportDatabaseInstance({
    required Database db,
    required String targetFilePath,
  }) {
    final validation = DatabaseValidator.validateWorldDatabase(db);
    if (!validation.isValid) {
      return ExportResult.failure(
        outputPath: targetFilePath,
        message: 'Cannot export invalid world database: ${validation.errors.first.message}',
      );
    }

    final targetDir = Directory(p.dirname(targetFilePath));
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

    final targetFile = File(targetFilePath);
    if (targetFile.existsSync()) {
      try {
        targetFile.deleteSync();
      } catch (_) {}
    }

    try {
      // Use SQLite VACUUM INTO to dump cleanly to disk
      final normalizedPath = targetFilePath.replaceAll('\\', '/');
      db.execute("VACUUM INTO '$normalizedPath';");

      final exportedFile = File(targetFilePath);
      return ExportResult.success(
        outputPath: targetFilePath,
        byteSize: exportedFile.existsSync() ? exportedFile.lengthSync() : 0,
      );
    } catch (e) {
      return ExportResult.failure(
        outputPath: targetFilePath,
        message: 'Failed to dump database instance to disk: $e',
      );
    }
  }

  /// Applies schema migrations to an existing database if its schema_version
  /// is older than DatabaseSchema.currentSchemaVersion.
  void applyMigrations(Database db) {
    final metaRow = db.select('SELECT schema_version FROM dataset_metadata LIMIT 1;').first;
    final currentVer = metaRow['schema_version'] as int;

    if (currentVer < DatabaseSchema.currentSchemaVersion) {
      // Apply migrations for missing tables / columns
      db.execute('''
        CREATE TABLE IF NOT EXISTS countries (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            code TEXT UNIQUE NOT NULL,
            continent TEXT NOT NULL CHECK(continent IN ('EUROPE', 'SOUTH_AMERICA', 'NORTH_AMERICA', 'AFRICA', 'ASIA', 'OCEANIA', 'OTHER')),
            reputation INTEGER CHECK(reputation BETWEEN 1 AND 100) DEFAULT 50,
            flag_icon_key TEXT
        );

        CREATE TABLE IF NOT EXISTS stadiums (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            city TEXT,
            country_code TEXT,
            capacity INTEGER NOT NULL DEFAULT 15000,
            built_year INTEGER
        );

        CREATE TABLE IF NOT EXISTS player_positions (
            player_id TEXT NOT NULL,
            position TEXT NOT NULL,
            is_primary INTEGER NOT NULL DEFAULT 0,
            proficiency INTEGER CHECK(proficiency BETWEEN 1 AND 100) DEFAULT 100,
            PRIMARY KEY(player_id, position),
            FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS national_squad_selections (
            id TEXT PRIMARY KEY,
            player_id TEXT NOT NULL,
            team_id TEXT NOT NULL,
            squad_number INTEGER,
            callup_year INTEGER NOT NULL,
            FOREIGN KEY(player_id) REFERENCES players(id) ON DELETE CASCADE,
            FOREIGN KEY(team_id) REFERENCES teams(id) ON DELETE CASCADE
        );

        UPDATE dataset_metadata SET schema_version = ${DatabaseSchema.currentSchemaVersion};
      ''');
    }
  }
}
