import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/publish/ssh_config.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('ssh-config');
    await Directory(p.join(home.path, '.ssh')).create(recursive: true);
  });

  tearDown(() async {
    if (await home.exists()) {
      await home.delete(recursive: true);
    }
  });

  Future<SshConfig> write(String contents, {String name = 'config'}) async {
    final file = File(p.join(home.path, '.ssh', name));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
    return SshConfig.load(path: file.path, homeDirectory: home.path);
  }

  test('a missing config reads as empty', () async {
    final config = await SshConfig.load(
      path: p.join(home.path, '.ssh', 'nothing'),
      homeDirectory: home.path,
    );

    expect(config.forHost('example.com').isEmpty, isTrue);
  });

  test('no home means no config', () async {
    final config = await SshConfig.load(homeDirectory: null);

    expect(config.forHost('example.com').isEmpty, isTrue);
  });

  test('reads a quoted IdentityAgent path holding spaces', () async {
    // The shape every 1Password setup has.
    final config = await write('''
Host *
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
''');

    expect(
      config.forHost('example.com').identityAgent,
      p.join(
        home.path,
        'Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock',
      ),
    );
  });

  test('a host block only applies to the hosts it names', () async {
    final config = await write('''
Host deploy.example.com
  IdentityAgent /tmp/deploy.sock
  IdentityFile ~/.ssh/deploy

Host other.example.com
  IdentityFile ~/.ssh/other
''');

    final deploy = config.forHost('deploy.example.com');
    expect(deploy.identityAgent, '/tmp/deploy.sock');
    expect(deploy.identityFiles, [p.join(home.path, '.ssh', 'deploy')]);

    final elsewhere = config.forHost('other.example.com');
    expect(elsewhere.identityAgent, isNull);
    expect(elsewhere.identityFiles, [p.join(home.path, '.ssh', 'other')]);
  });

  test('a wildcard block applies alongside a named one', () async {
    final config = await write('''
Host *
  IdentityAgent /tmp/agent.sock

Host deploy.example.com
  IdentityFile ~/.ssh/deploy
''');

    final resolved = config.forHost('deploy.example.com');
    expect(resolved.identityAgent, '/tmp/agent.sock');
    expect(resolved.identityFiles, [p.join(home.path, '.ssh', 'deploy')]);
  });

  test('the first value for a keyword wins, as ssh resolves it', () async {
    final config = await write('''
Host deploy.example.com
  IdentityAgent /tmp/first.sock

Host *
  IdentityAgent /tmp/second.sock
''');

    expect(
      config.forHost('deploy.example.com').identityAgent,
      '/tmp/first.sock',
    );
  });

  test('identity files accumulate in the order they are named', () async {
    final config = await write('''
Host *
  IdentityFile ~/.ssh/one
  IdentityFile ~/.ssh/two
''');

    expect(config.forHost('anything').identityFiles, [
      p.join(home.path, '.ssh', 'one'),
      p.join(home.path, '.ssh', 'two'),
    ]);
  });

  test('a glob pattern matches, and a negated one excludes', () async {
    final config = await write('''
Host *.example.com !private.example.com
  IdentityFile ~/.ssh/shared
''');

    expect(config.forHost('deploy.example.com').identityFiles, isNotEmpty);
    expect(config.forHost('private.example.com').identityFiles, isEmpty);
    expect(config.forHost('example.org').identityFiles, isEmpty);
  });

  test('IdentitiesOnly is carried through', () async {
    final config = await write('''
Host deploy.example.com
  IdentityFile ~/.ssh/deploy
  IdentitiesOnly yes
''');

    expect(config.forHost('deploy.example.com').identitiesOnly, isTrue);
    expect(config.forHost('other.example.com').identitiesOnly, isFalse);
  });

  test(
    'IdentityAgent none disables the agent rather than naming one',
    () async {
      final config = await write('''
Host deploy.example.com
  IdentityAgent none

Host *
  IdentityAgent /tmp/agent.sock
''');

      expect(config.forHost('deploy.example.com').identityAgent, isNull);
      expect(
        config.forHost('other.example.com').identityAgent,
        '/tmp/agent.sock',
      );
    },
  );

  test('keyword=value is read the same as keyword value', () async {
    final config = await write('''
Host=deploy.example.com
  IdentityFile=~/.ssh/deploy
''');

    expect(config.forHost('deploy.example.com').identityFiles, [
      p.join(home.path, '.ssh', 'deploy'),
    ]);
  });

  test('comments and blank lines are ignored', () async {
    final config = await write('''
# a comment
Host deploy.example.com
  # another
  IdentityFile ~/.ssh/deploy

''');

    expect(config.forHost('deploy.example.com').identityFiles, hasLength(1));
  });

  test('keywords are matched without regard to case', () async {
    final config = await write('''
HOST deploy.example.com
  identityagent /tmp/agent.sock
  IDENTITYFILE ~/.ssh/deploy
''');

    final resolved = config.forHost('deploy.example.com');
    expect(resolved.identityAgent, '/tmp/agent.sock');
    expect(resolved.identityFiles, hasLength(1));
  });

  test('a Match block is skipped rather than guessed at', () async {
    final config = await write('''
Match host deploy.example.com exec "true"
  IdentityFile ~/.ssh/conditional

Host deploy.example.com
  IdentityFile ~/.ssh/deploy
''');

    // Applying a condition this cannot evaluate would offer a key for the
    // wrong host.
    expect(config.forHost('deploy.example.com').identityFiles, [
      p.join(home.path, '.ssh', 'deploy'),
    ]);
  });

  test('an Include pulls in another file', () async {
    await File(p.join(home.path, '.ssh', 'extra')).writeAsString('''
Host deploy.example.com
  IdentityFile ~/.ssh/deploy
''');
    final config = await write('''
Include extra

Host *
  IdentityAgent /tmp/agent.sock
''');

    final resolved = config.forHost('deploy.example.com');
    expect(resolved.identityFiles, [p.join(home.path, '.ssh', 'deploy')]);
    expect(resolved.identityAgent, '/tmp/agent.sock');
  });

  test('an Include glob pulls in every file it matches', () async {
    final directory = Directory(p.join(home.path, '.ssh', 'config.d'));
    await directory.create(recursive: true);
    await File(p.join(directory.path, '10-one.conf')).writeAsString('''
Host one.example.com
  IdentityFile ~/.ssh/one
''');
    await File(p.join(directory.path, '20-two.conf')).writeAsString('''
Host two.example.com
  IdentityFile ~/.ssh/two
''');

    final config = await write('Include config.d/*.conf\n');

    expect(config.forHost('one.example.com').identityFiles, hasLength(1));
    expect(config.forHost('two.example.com').identityFiles, hasLength(1));
  });

  test('an Include loop does not read forever', () async {
    await File(p.join(home.path, '.ssh', 'a')).writeAsString('Include b\n');
    await File(p.join(home.path, '.ssh', 'b')).writeAsString('Include a\n');

    final config = await write('Include a\n');

    expect(config.forHost('anything').isEmpty, isTrue);
  });

  test('the host block survives an Include in the middle of it', () async {
    await File(p.join(home.path, '.ssh', 'extra')).writeAsString('# nothing\n');
    final config = await write('''
Host deploy.example.com
  IdentityFile ~/.ssh/before
  Include extra
  IdentityFile ~/.ssh/after
''');

    expect(config.forHost('deploy.example.com').identityFiles, [
      p.join(home.path, '.ssh', 'before'),
      p.join(home.path, '.ssh', 'after'),
    ]);
  });

  test('%d expands to the home directory', () async {
    final config = await write('''
Host *
  IdentityFile %d/.ssh/token
''');

    expect(config.forHost('anything').identityFiles, [
      p.join(home.path, '.ssh', 'token'),
    ]);
  });

  test('%h and %r expand to the host and the user', () async {
    final config = await write('''
Host *
  IdentityFile ~/.ssh/%r@%h
''');

    expect(config.forHost('example.com', user: 'deploy').identityFiles, [
      p.join(home.path, '.ssh', 'deploy@example.com'),
    ]);
  });
}
