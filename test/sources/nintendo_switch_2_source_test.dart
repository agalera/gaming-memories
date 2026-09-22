import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/mtp_client.dart';
import 'package:gaming_memories/sources/nintendo_switch_2_source.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory source;
  late Directory output;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('gaming-memories-switch2-');
    output = await Directory.systemTemp.createTemp('gaming-memories-output-');
  });

  tearDown(() async {
    await source.delete(recursive: true);
    await output.delete(recursive: true);
  });

  AppSettings settings({
    bool useCustomPath = true,
    List<String> ignoredFolders = const ['Otra carpeta'],
  }) {
    return AppSettings(
      outputPath: output.path,
      nintendoSwitch2: NintendoSwitch2Settings(
        enabled: true,
        useCustomPath: useCustomPath,
        sourcePath: useCustomPath ? source.path : '',
        ignoredFolders: ignoredFolders,
      ),
    );
  }

  Future<void> write(String game, String name, String contents) async {
    final directory = Directory(p.join(source.path, game));
    await directory.create(recursive: true);
    await File(p.join(directory.path, name)).writeAsString(contents);
  }

  test(
    'imports copied screenshots and clips under their game folders',
    () async {
      await write('Mario Kart World', '2025060720031600_s.jpg', 'screenshot');
      await write('Mario Kart World', '2025060720031700_s.mp4', 'clip');
      await write('Mario Kart World', '2025060720031800_c.jpg', 'copy');
      await write('Mario Kart World', 'notes.txt', 'notes');
      await write('Otra carpeta', '2025060720031900_s.jpg', 'ignored');

      final result = await const NintendoSwitch2Source().collect(settings());

      final album = p.join(
        output.path,
        'Nintendo Switch 2',
        'Mario Kart World',
      );
      expect(result.imported, 2);
      expect(result.skipped, 0);
      expect(
        File(p.join(album, '2025060720031600_s.jpg')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(album, '2025060720031700_s.mp4')).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(output.path, 'Nintendo Switch 2', 'Otra carpeta'))
            .existsSync(),
        isFalse,
      );
    },
  );

  test('uses the configured ignored folders case-insensitively', () async {
    await write('MARIO KART WORLD', '2025060720031600_s.jpg', 'ignored');
    await write('Zelda', '2025060720031700_s.jpg', 'imported');

    final result = await const NintendoSwitch2Source().collect(
      settings(ignoredFolders: const ['mario kart world']),
    );

    expect(result.imported, 1);
    expect(
      Directory(p.join(output.path, 'Nintendo Switch 2', 'Zelda')).existsSync(),
      isTrue,
    );
  });

  test('pulls only new supported captures from a connected console', () async {
    final existing = File(
      p.join(
        output.path,
        'Nintendo Switch 2',
        'Mario Kart World',
        '2025060720031600_s.jpg',
      ),
    );
    await existing.parent.create(recursive: true);
    await existing.writeAsString('existing');
    final mtp = _FakeMtpClient(
      folderValues: const [
        MtpFolder(id: '10', name: 'Mario Kart World'),
        MtpFolder(id: '20', name: 'Otra carpeta'),
      ],
      fileValues: const [
        MtpFile(
          id: '11',
          name: '2025060720031600_s.jpg',
          size: 4,
          parentId: '10',
        ),
        MtpFile(
          id: '12',
          name: '2025060720031700_s.mp4',
          size: 4,
          parentId: '10',
        ),
        MtpFile(
          id: '13',
          name: '2025060720031800_c.jpg',
          size: 4,
          parentId: '10',
        ),
        MtpFile(
          id: '21',
          name: '2025060720031900_s.jpg',
          size: 4,
          parentId: '20',
        ),
      ],
    );
    final source = NintendoSwitch2Source(
      mtpClient: mtp,
      usbDeviceFinder: const _FakeUsbDeviceFinder(found: true),
      operatingSystem: 'linux',
    );

    final result = await source.collect(settings(useCustomPath: false));

    expect(result.imported, 1);
    expect(result.skipped, 1);
    expect(mtp.pulled.map((pull) => pull.file.id), ['12']);
    expect(
      File(
        p.join(
          output.path,
          'Nintendo Switch 2',
          'Mario Kart World',
          '2025060720031700_s.mp4',
        ),
      ).existsSync(),
      isTrue,
    );
  });

  test('warns when no console is sharing its album', () async {
    final mtp = _FakeMtpClient();
    final result = await NintendoSwitch2Source(
      mtpClient: mtp,
      usbDeviceFinder: const _FakeUsbDeviceFinder(found: false),
      operatingSystem: 'linux',
    ).collect(settings(useCustomPath: false));

    expect(result.warning, contains('No Nintendo Switch 2'));
    expect(mtp.ensureAvailableCalls, 0);
  });

  test('explains that direct USB collection is Linux-only', () async {
    final result = await const NintendoSwitch2Source(operatingSystem: 'macos')
        .collect(settings(useCustomPath: false));

    expect(result.warning, contains('available on Linux'));
  });

  test('reports the libmtp requirement when its tools are missing', () async {
    final mtp = _FakeMtpClient(
      failure: const MtpException(
        MtpFailure.missingTools,
        'Missing libmtp tools.',
      ),
    );
    final result = await NintendoSwitch2Source(
      mtpClient: mtp,
      usbDeviceFinder: const _FakeUsbDeviceFinder(found: true),
      operatingSystem: 'linux',
    ).collect(settings(useCustomPath: false));

    expect(result.warning, contains('requires the libmtp tools'));
  });

  test('explains how to release a busy console', () async {
    final mtp = _FakeMtpClient(
      failure: const MtpException(
        MtpFailure.busy,
        'Another program is using the MTP device.',
      ),
    );
    final result = await NintendoSwitch2Source(
      mtpClient: mtp,
      usbDeviceFinder: const _FakeUsbDeviceFinder(found: true),
      operatingSystem: 'linux',
    ).collect(settings(useCustomPath: false));

    expect(result.warning, contains('Eject it from the file manager'));
  });

  test('recognizes only original Switch 2 screenshots and clips', () {
    expect(isNintendoSwitch2Capture('2026032619431800_s.jpg'), isTrue);
    expect(isNintendoSwitch2Capture('2026032619431800_s.MP4'), isTrue);
    expect(isNintendoSwitch2Capture('2026032619431800_c.jpg'), isFalse);
    expect(isNintendoSwitch2Capture('2026032619431800.jpg'), isFalse);
    expect(isNintendoSwitch2Capture('2026032619431800_s.txt'), isFalse);
  });
}

class _FakeMtpClient implements MtpClient {
  _FakeMtpClient({
    this.folderValues = const [],
    this.fileValues = const [],
    this.failure,
  });

  final List<MtpFolder> folderValues;
  final List<MtpFile> fileValues;
  final MtpException? failure;
  final pulled = <MtpPull>[];
  var ensureAvailableCalls = 0;

  @override
  Future<void> ensureAvailable() async {
    ensureAvailableCalls++;
    if (failure != null) {
      throw failure!;
    }
  }

  @override
  Future<List<MtpFile>> files() async => fileValues;

  @override
  Future<List<MtpFolder>> folders() async => folderValues;

  @override
  Future<void> pull(
    List<MtpPull> pulls, {
    MtpProgressCallback? onProgress,
  }) async {
    pulled.addAll(pulls);
    for (var index = 0; index < pulls.length; index++) {
      final pull = pulls[index];
      await File(pull.path).parent.create(recursive: true);
      await File(pull.path).writeAsBytes(List.filled(pull.file.size, index));
      onProgress?.call(index + 1, pulls.length);
    }
  }
}

class _FakeUsbDeviceFinder implements UsbDeviceFinder {
  const _FakeUsbDeviceFinder({required this.found});

  final bool found;

  @override
  Future<UsbDevice?> find({
    required String vendorId,
    required String productId,
  }) async => found
      ? UsbDevice(
          vendorId: vendorId,
          productId: productId,
          product: 'Nintendo Switch 2',
          serial: 'HAE100',
        )
      : null;
}
