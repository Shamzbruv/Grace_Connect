import 'package:image_picker/image_picker.dart';

import '../services/community_service.dart';

Future<String> uploadCommunityMediaXFile({
  required CommunityService service,
  required XFile media,
  required String path,
  required String contentType,
}) async {
  return service.uploadMediaBytes(
    await media.readAsBytes(),
    path,
    contentType: contentType,
  );
}
