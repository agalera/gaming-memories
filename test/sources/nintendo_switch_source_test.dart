import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/models/app_settings.dart';
import 'package:gaming_memories/services/mtp_client.dart';
import 'package:gaming_memories/sources/nintendo_switch_source.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory source;
  late Directory output;

  setUp(() async {
    source = await Directory.systemTemp.createTemp('gaming-memories-switch-');
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
      nintendoSwitch: NintendoSwitchSettings(
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
      await write('Hollow Knight', '2023020909500400_s.jpg', 'screenshot');
      await write('Hollow Knight', '2023020909500500_s.mp4', 'clip');
      await write('Hollow Knight', '2023020909500600_c.jpg', 'copy');
      await write('Hollow Knight', 'notes.txt', 'notes');
      await write('Otra carpeta', '2023020909500700_s.jpg', 'ignored');

      final result = await const NintendoSwitchSource().collect(settings());

      final album = p.join(output.path, 'Nintendo Switch', 'Hollow Knight');
      expect(result.imported, 2);
      expect(result.skipped, 0);
      expect(
        File(p.join(album, '2023020909500400_s.jpg')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(album, '2023020909500500_s.mp4')).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(output.path, 'Nintendo Switch', 'Otra carpeta'))
            .existsSync(),
        isFalse,
      );
    },
  );

  test('keeps the Switch album separate from the Switch 2 album', () async {
    await write('Celeste', '2023020909500400_s.jpg', 'screenshot');

    await const NintendoSwitchSource().collect(settings());

    expect(
      Directory(p.join(output.path, 'Nintendo Switch 2')).existsSync(),
      isFalse,
    );
  });

  test('pulls only new supported captures from a connected console', () async {
    final existing = File(
      p.join(
        output.path,
        'Nintendo Switch',
        'Celeste',
        '2023020909500400_s.jpg',
      ),
    );
    await existing.parent.create(recursive: true);
    await existing.writeAsString('existing');
    final mtp = _FakeMtpClient(
      folderValues: const [
        MtpFolder(id: '10', name: 'Celeste'),
        MtpFolder(id: '20', name: 'Otra carpeta'),
      ],
      fileValues: const [
        MtpFile(
          id: '11',
          name: '2023020909500400_s.jpg',
          size: 4,
          parentId: '10',
        ),
        MtpFile(
          id: '12',
          name: '2023020909500500_s.mp4',
          size: 4,
          parentId: '10',
        ),
        MtpFile(
          id: '13',
          name: '2023020909500600_c.jpg',
          size: 4,
          parentId: '10',
        ),
        MtpFile(
          id: '21',
          name: '2023020909500700_s.jpg',
          size: 4,
          parentId: '20',
        ),
      ],
    );
    final usb = _FakeUsbDeviceFinder(found: true);
    final source = NintendoSwitchSource(
      mtpClient: mtp,
      usbDeviceFinder: usb,
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
          'Nintendo Switch',
          'Celeste',
          '2023020909500500_s.mp4',
        ),
      ).existsSync(),
      isTrue,
    );
  });

  test('looks for the album product ID the Switch reports', () async {
    final usb = _FakeUsbDeviceFinder(found: false);
    await NintendoSwitchSource(
      mtpClient: _FakeMtpClient(),
      usbDeviceFinder: usb,
      operatingSystem: 'linux',
    ).collect(settings(useCustomPath: false));

    expect(usb.vendorIds, ['057e']);
    expect(usb.productIds, ['201d']);
  });

  test('warns when no console is sharing its album', () async {
    final mtp = _FakeMtpClient();
    final result = await NintendoSwitchSource(
      mtpClient: mtp,
      usbDeviceFinder: _FakeUsbDeviceFinder(found: false),
      operatingSystem: 'linux',
    ).collect(settings(useCustomPath: false));

    expect(result.warning, contains('No Nintendo Switch is currently sharing'));
    expect(mtp.ensureAvailableCalls, 0);
  });

  test('explains that direct USB collection is Linux-only', () async {
    final result = await const NintendoSwitchSource(operatingSystem: 'macos')
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
    final result = await NintendoSwitchSource(
      mtpClient: mtp,
      usbDeviceFinder: _FakeUsbDeviceFinder(found: true),
      operatingSystem: 'linux',
    ).collect(settings(useCustomPath: false));

    expect(result.warning, contains('requires the libmtp tools'));
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
  _FakeUsbDeviceFinder({required this.found});

  final bool found;
  final vendorIds = <String>[];
  final productIds = <String>[];

  @override
  Future<UsbDevice?> find({
    required String vendorId,
    required String productId,
  }) async {
    vendorIds.add(vendorId);
    productIds.add(productId);
    return found
        ? UsbDevice(
            vendorId: vendorId,
            productId: productId,
            product: 'Nintendo Switch',
            serial: 'XAJ100',
          )
        : null;
  }
}
