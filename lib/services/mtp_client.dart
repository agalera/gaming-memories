import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const mtpRequiredTools = ['mtp-folders', 'mtp-files', 'mtp-connect'];
const _mtpPullBatchSize = 500;

enum MtpFailure {
  busy,
  staleSession,
  noDevice,
  missingTools,
  command,
  incompleteTransfer,
}

class MtpException implements Exception {
  const MtpException(this.failure, this.message);

  final MtpFailure failure;
  final String message;

  @override
  String toString() => message;
}

class MtpFolder {
  const MtpFolder({required this.id, required this.name});

  final String id;
  final String name;
}

class MtpFile {
  const MtpFile({
    required this.id,
    required this.name,
    required this.size,
    required this.parentId,
  });

  final String id;
  final String name;
  final int size;
  final String parentId;
}

class MtpPull {
  const MtpPull({required this.file, required this.path});

  final MtpFile file;
  final String path;
}

typedef MtpProgressCallback = void Function(int completed, int total);

abstract interface class MtpClient {
  Future<void> ensureAvailable();

  Future<List<MtpFolder>> folders();

  Future<List<MtpFile>> files();

  Future<void> pull(List<MtpPull> pulls, {MtpProgressCallback? onProgress});
}

class MtpToolResult {
  const MtpToolResult({required this.output, required this.exitCode});

  final String output;
  final int exitCode;
}

abstract interface class MtpToolRunner {
  Future<bool> isAvailable(String executable);

  Future<MtpToolResult> run(String executable, List<String> arguments);
}

class ProcessMtpToolRunner implements MtpToolRunner {
  const ProcessMtpToolRunner();

  @override
  Future<bool> isAvailable(String executable) async {
    final path = Platform.environment['PATH'];
    if (path == null || path.isEmpty) {
      return false;
    }
    final separator = Platform.isWindows ? ';' : ':';
    for (final directory in path.split(separator)) {
      if (directory.isEmpty) {
        continue;
      }
      if (await File(p.join(directory, executable)).exists()) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<MtpToolResult> run(String executable, List<String> arguments) async {
    try {
      final result = await Process.run(executable, arguments);
      final stdout = result.stdout.toString();
      final stderr = result.stderr.toString();
      return MtpToolResult(
        output: [
          if (stdout.isNotEmpty) stdout,
          if (stderr.isNotEmpty) stderr,
        ].join('\n'),
        exitCode: result.exitCode,
      );
    } on ProcessException catch (exception) {
      throw MtpException(
        MtpFailure.command,
        '$executable could not be started: ${exception.message}',
      );
    }
  }
}

class LibMtpClient implements MtpClient {
  const LibMtpClient({this.runner = const ProcessMtpToolRunner()});

  final MtpToolRunner runner;

  @override
  Future<void> ensureAvailable() async {
    final missing = <String>[];
    for (final tool in mtpRequiredTools) {
      if (!await runner.isAvailable(tool)) {
        missing.add(tool);
      }
    }
    if (missing.isNotEmpty) {
      throw MtpException(
        MtpFailure.missingTools,
        'Missing libmtp tools: ${missing.join(', ')}.',
      );
    }
  }

  @override
  Future<List<MtpFolder>> folders() async {
    final result = await _run('mtp-folders');
    return parseMtpFolders(result.output);
  }

  @override
  Future<List<MtpFile>> files() async {
    final result = await _run('mtp-files');
    return parseMtpFiles(result.output);
  }

  @override
  Future<void> pull(
    List<MtpPull> pulls, {
    MtpProgressCallback? onProgress,
  }) async {
    for (var start = 0; start < pulls.length; start += _mtpPullBatchSize) {
      final end = (start + _mtpPullBatchSize).clamp(0, pulls.length);
      final batch = pulls.sublist(start, end);
      final arguments = <String>[];
      for (final pull in batch) {
        await File(pull.path).parent.create(recursive: true);
        arguments.addAll(['--getfile', pull.file.id, pull.path]);
      }

      await _run('mtp-connect', arguments);
      await verifyMtpPulls(batch);
      onProgress?.call(end, pulls.length);
    }
  }

  Future<MtpToolResult> _run(
    String executable, [
    List<String> arguments = const [],
  ]) async {
    final result = await runner.run(executable, arguments);
    final outputError = mtpOutputError(result.output);
    if (outputError != null) {
      throw outputError;
    }
    if (result.exitCode != 0) {
      final output = result.output.trim().replaceAll(RegExp(r'\s+'), ' ');
      final detail = output.isEmpty
          ? ''
          : ' ${output.length <= 400 ? output : '${output.substring(0, 399)}…'}';
      throw MtpException(
        MtpFailure.command,
        '$executable failed with exit code ${result.exitCode}.$detail',
      );
    }
    return result;
  }
}

MtpException? mtpOutputError(String output) {
  if (output.contains('libusb_claim_interface() reports device is busy')) {
    return const MtpException(
      MtpFailure.busy,
      'Another program is using the MTP device.',
    );
  }
  if (output.contains('Unable to read device information')) {
    return const MtpException(
      MtpFailure.staleSession,
      'The console kept an old MTP session open.',
    );
  }
  if (output.contains('No raw devices found') ||
      output.contains('No devices.')) {
    return const MtpException(MtpFailure.noDevice, 'No MTP device answered.');
  }
  return null;
}

List<MtpFolder> parseMtpFolders(String output) {
  final folders = <MtpFolder>[];
  for (final line in const LineSplitter().convert(output)) {
    final separator = line.indexOf('\t');
    if (separator < 1) {
      continue;
    }
    final id = line.substring(0, separator).trim();
    if (!_isDigits(id)) {
      continue;
    }
    folders.add(MtpFolder(id: id, name: line.substring(separator + 1).trim()));
  }
  return folders;
}

List<MtpFile> parseMtpFiles(String output) {
  final files = <MtpFile>[];
  String? id;
  var name = '';
  var size = 0;
  var parentId = '';

  void closeBlock() {
    if (id != null && name.isNotEmpty) {
      files.add(MtpFile(id: id!, name: name, size: size, parentId: parentId));
    }
    id = null;
    name = '';
    size = 0;
    parentId = '';
  }

  for (final line in const LineSplitter().convert(output)) {
    final trimmed = line.trim();
    if (trimmed.startsWith('File ID: ')) {
      closeBlock();
      final value = trimmed.substring('File ID: '.length).trim();
      if (_isDigits(value)) {
        id = value;
      }
    } else if (id == null) {
      continue;
    } else if (trimmed.startsWith('Filename: ')) {
      name = trimmed.substring('Filename: '.length).trim();
    } else if (trimmed.startsWith('File size ')) {
      final fields = trimmed.substring('File size '.length).split(' ');
      size = int.tryParse(fields.first) ?? 0;
    } else if (trimmed.startsWith('Parent ID: ')) {
      parentId = trimmed.substring('Parent ID: '.length).trim();
    }
  }
  closeBlock();
  return files;
}

Future<void> verifyMtpPulls(List<MtpPull> pulls) async {
  for (final pull in pulls) {
    final source = File(pull.path);
    if (!await source.exists()) {
      throw MtpException(
        MtpFailure.incompleteTransfer,
        '${pull.file.name} was not copied off the console.',
      );
    }
    final length = await source.length();
    if (length != pull.file.size) {
      throw MtpException(
        MtpFailure.incompleteTransfer,
        '${pull.file.name} arrived with $length bytes; the console reported ${pull.file.size}.',
      );
    }
  }
}

bool _isDigits(String value) =>
    value.isNotEmpty &&
    value.codeUnits.every((unit) => unit >= 48 && unit <= 57);

class UsbDevice {
  const UsbDevice({
    required this.vendorId,
    required this.productId,
    required this.product,
    required this.serial,
  });

  final String vendorId;
  final String productId;
  final String product;
  final String serial;
}

abstract interface class UsbDeviceFinder {
  Future<UsbDevice?> find({
    required String vendorId,
    required String productId,
  });
}

class LinuxSysfsUsbDeviceFinder implements UsbDeviceFinder {
  const LinuxSysfsUsbDeviceFinder({this.rootPath = '/sys/bus/usb/devices'});

  final String rootPath;

  @override
  Future<UsbDevice?> find({
    required String vendorId,
    required String productId,
  }) async {
    List<FileSystemEntity> entries;
    try {
      entries = await Directory(rootPath).list(followLinks: false).toList();
    } on FileSystemException {
      return null;
    }

    for (final entry in entries) {
      final vendor = await _attribute(entry, 'idVendor');
      final product = await _attribute(entry, 'idProduct');
      if (vendor == null ||
          product == null ||
          vendor.toLowerCase() != vendorId.toLowerCase() ||
          product.toLowerCase() != productId.toLowerCase()) {
        continue;
      }
      return UsbDevice(
        vendorId: vendor,
        productId: product,
        product: await _attribute(entry, 'product') ?? '',
        serial: await _attribute(entry, 'serial') ?? '',
      );
    }
    return null;
  }

  Future<String?> _attribute(FileSystemEntity entry, String name) async {
    try {
      return (await File(p.join(entry.path, name)).readAsString()).trim();
    } on FileSystemException {
      return null;
    }
  }
}
