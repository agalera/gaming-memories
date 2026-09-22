import '../models/app_settings.dart';
import '../services/folder_access_service.dart';
import '../services/media_importer.dart';
import '../services/mtp_client.dart';
import 'nintendo_switch_album.dart';

class NintendoSwitchSource extends NintendoSwitchAlbumSource {
  const NintendoSwitchSource({
    super.importer = const MediaImporter(),
    super.mtpClient = const LibMtpClient(),
    super.usbDeviceFinder = const LinuxSysfsUsbDeviceFinder(),
    super.operatingSystem,
  });

  static const platform = 'Nintendo Switch';

  @override
  String get id => 'nintendo_switch';

  @override
  String get name => platform;

  /// The Switch and the Switch Lite share this product ID, which libmtp lists
  /// as one device.
  @override
  String get albumProductId => '201d';

  @override
  String get folderGrantId => FolderGrantIds.nintendoSwitch;

  @override
  NintendoSwitchSettings config(AppSettings settings) =>
      settings.nintendoSwitch;

  @override
  AppSettings withFolderPath(AppSettings settings, String path) {
    return settings.copyWith(
      nintendoSwitch: settings.nintendoSwitch.copyWith(
        enabled: true,
        useCustomPath: true,
        sourcePath: path,
      ),
    );
  }
}
