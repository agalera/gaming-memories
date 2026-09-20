import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/mtp_client.dart';
import 'package:path/path.dart' as p;

void main() {
  test('parses libmtp folder listings past warnings', () {
    final folders = parseMtpFolders('''
LIBMTP WARNING: no MTP vendor extension
Storage: Album
5905\tMario Kart World
5909\tYakuza 0 Director's Cut
OK.
''');

    expect(folders, hasLength(2));
    expect(folders.first.id, '5905');
    expect(folders.first.name, 'Mario Kart World');
    expect(folders.last.name, "Yakuza 0 Director's Cut");
  });

  test('parses complete and truncated libmtp file blocks', () {
    final files = parseMtpFiles('''
libmtp version: 1.1.23
File ID: 5906
   Filename: 2026032619431800_s.jpg
   File size 502016 (0x000000000007A900) bytes
   Parent ID: 5905
   Storage ID: 0x00040001
File ID: 5913
   Filename: 2026032619431900_s.mp4
   Parent ID: 5909
''');

    expect(files, hasLength(2));
    expect(files.first.id, '5906');
    expect(files.first.name, '2026032619431800_s.jpg');
    expect(files.first.size, 502016);
    expect(files.first.parentId, '5905');
    expect(files.last.id, '5913');
    expect(files.last.parentId, '5909');
  });

  test('recognizes failures reported in successful libmtp output', () {
    expect(
      mtpOutputError(
        'libusb_claim_interface() reports device is busy, likely in use by GVFS',
      )?.failure,
      MtpFailure.busy,
    );
    expect(
      mtpOutputError('Unable to read device information')?.failure,
      MtpFailure.staleSession,
    );
    expect(
      mtpOutputError('No raw devices found')?.failure,
      MtpFailure.noDevice,
    );
    expect(mtpOutputError('5905\tMario Kart World'), isNull);
  });

  test('reports all missing libmtp tools', () async {
    final client = LibMtpClient(runner: _FakeRunner(available: const {}));

    await expectLater(
      client.ensureAvailable(),
      throwsA(
        isA<MtpException>()
            .having(
              (error) => error.failure,
              'failure',
              MtpFailure.missingTools,
            )
            .having(
              (error) => error.message,
              'message',
              contains('mtp-connect'),
            ),
      ),
    );
  });

  test('pulls in batches and verifies every transferred size', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gaming-memories-mtp-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final runner = _FakeRunner(available: mtpRequiredTools.toSet());
    runner.onRun = (executable, arguments) async {
      if (executable == 'mtp-connect') {
        for (var index = 0; index < arguments.length; index += 3) {
          await File(arguments[index + 2]).writeAsBytes([1, 2]);
        }
      }
      return const MtpToolResult(output: 'OK.', exitCode: 0);
    };
    final pulls = [
      for (var index = 0; index < 501; index++)
        MtpPull(
          file: MtpFile(
            id: '$index',
            name: 'capture-$index.jpg',
            size: 2,
            parentId: '10',
          ),
          path: p.join(directory.path, '$index', 'capture.jpg'),
        ),
    ];

    await LibMtpClient(runner: runner).pull(pulls);

    expect(
      runner.calls.where((call) => call.executable == 'mtp-connect'),
      hasLength(2),
    );
  });

  test('reports a transfer whose file is shorter than advertised', () async {
    final directory = await Directory.systemTemp.createTemp(
      'gaming-memories-mtp-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'capture.jpg'));
    await file.writeAsBytes([1]);

    await expectLater(
      verifyMtpPulls([
        MtpPull(
          file: const MtpFile(
            id: '1',
            name: 'capture.jpg',
            size: 500,
            parentId: '10',
          ),
          path: file.path,
        ),
      ]),
      throwsA(
        isA<MtpException>().having(
          (error) => error.failure,
          'failure',
          MtpFailure.incompleteTransfer,
        ),
      ),
    );
  });

  test('finds the Switch 2 album USB product in Linux sysfs', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'gaming-memories-sysfs-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final root = Directory(p.join(temporary.path, 'bus'))..createSync();
    final regular = Directory(p.join(root.path, '10-1'))..createSync();
    await File(p.join(regular.path, 'idVendor')).writeAsString('057e\n');
    await File(p.join(regular.path, 'idProduct')).writeAsString('2060\n');
    final album = Directory(p.join(temporary.path, 'devices', '10-2'))
      ..createSync(recursive: true);
    await File(p.join(album.path, 'idVendor')).writeAsString('057E\n');
    await File(p.join(album.path, 'idProduct')).writeAsString('2061\n');
    await File(p.join(album.path, 'product'))
        .writeAsString('Nintendo Switch 2\n');
    await File(p.join(album.path, 'serial')).writeAsString('HAE100\n');
    await Link(p.join(root.path, '10-2')).create(album.path);

    final device = await LinuxSysfsUsbDeviceFinder(rootPath: root.path)
        .find(vendorId: '057e', productId: '2061');

    expect(device?.product, 'Nintendo Switch 2');
    expect(device?.serial, 'HAE100');
  });
}

class _RunnerCall {
  const _RunnerCall(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

class _FakeRunner implements MtpToolRunner {
  _FakeRunner({required this.available});

  final Set<String> available;
  final calls = <_RunnerCall>[];
  Future<MtpToolResult> Function(String, List<String>)? onRun;

  @override
  Future<bool> isAvailable(String executable) async =>
      available.contains(executable);

  @override
  Future<MtpToolResult> run(String executable, List<String> arguments) async {
    calls.add(_RunnerCall(executable, List.unmodifiable(arguments)));
    return onRun?.call(executable, arguments) ??
        const MtpToolResult(output: 'OK.', exitCode: 0);
  }
}
