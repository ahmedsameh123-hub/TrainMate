import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

final _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Converts a [CameraImage] from [camera] to ML Kit [InputImage] (same approach as the official ML Kit example).
InputImage? inputImageFromCameraImage(
  CameraImage image,
  CameraController controller,
  CameraDescription camera,
) {
  final sensorOrientation = camera.sensorOrientation;
  InputImageRotation? rotation;
  if (Platform.isIOS) {
    rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
  } else if (Platform.isAndroid) {
    var rotationCompensation =
        _orientations[controller.value.deviceOrientation];
    if (rotationCompensation == null) return null;
    if (camera.lensDirection == CameraLensDirection.front) {
      rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      rotationCompensation =
          (sensorOrientation - rotationCompensation + 360) % 360;
    }
    rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
  }
  if (rotation == null) return null;

  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null ||
      (Platform.isAndroid && format != InputImageFormat.nv21) ||
      (Platform.isIOS && format != InputImageFormat.bgra8888)) {
    return null;
  }

  if (image.planes.length != 1) return null;
  final plane = image.planes.first;

  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}
