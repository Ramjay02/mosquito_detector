import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mosquito_detector/src/constants.dart';
import 'package:mosquito_detector/src/preprocess.dart';

void main() {
  test('golden pipeline stages', () async {
    final goldenDir = Directory('test/golden');
    final json = jsonDecode(await File('test/golden/golden.json').readAsString());
    final box = json['box_px_640'];
    
    // Load images
    final input640 = await File('test/golden/sample_input_640.png').readAsBytes();
    final refWB = await File('test/golden/sample_white_balanced.png').readAsBytes();
    final refCLAHE = await File('test/golden/sample_clahe.png').readAsBytes();
    final refUN = await File('test/golden/sample_unsharp.png').readAsBytes();
    final refCrop = await File('test/golden/sample_crop_224.png').readAsBytes();
    
    final img.Image? inImg = img.decodePng(input640);
    expect(inImg, isNotNull);
    
    // Compute focus score on stretched image (input is already 640x640 stretched)
    final focus = Preprocessor.focusScoreOfImage(inImg!);
    print('FOCUS_SCORE:$focus');
    
    // Run pipeline stages starting from input640 as stretched
    Uint8List wb = Preprocessor.grayWorldWhiteBalanceOnly(_imgToRgb(inImg));
    print('WB_MAD_RAW:${_madRaw(wb, _rgbFromPng(refWB))}');
    
    Uint8List clahe = Preprocessor.claheLabOnly(wb);
    print('CLAHE_MAD_RAW:${_madRaw(clahe, _rgbFromPng(refCLAHE))}');
    
    Uint8List unsharp = Preprocessor.unsharpMaskOnly(clahe);
    print('UNSHARP_MAD_RAW:${_madRaw(unsharp, _rgbFromPng(refUN))}');
    
    // Crop from reference unsharp
    Uint8List crop = Preprocessor.cropFromProcessed640(
      _rgbFromPng(refUN),
      x1: (box['x1'] as num).toDouble(),
      y1: (box['y1'] as num).toDouble(),
      x2: (box['x2'] as num).toDouble(),
      y2: (box['y2'] as num).toDouble(),
    );
    print('CROP_MAD_RAW:${_madRaw(crop, _rgbFromPng(refCrop))}');
  });
}

Uint8List _imgToRgb(img.Image image) {
  final Uint8List out = Uint8List(kDetectSize * kDetectSize * 3);
  for (int y = 0; y < kDetectSize; y++) {
    for (int x = 0; x < kDetectSize; x++) {
      final img.Pixel p = image.getPixel(x, y);
      final int idx = (y * kDetectSize + x) * 3;
      out[idx] = p.r.toInt();
      out[idx + 1] = p.g.toInt();
      out[idx + 2] = p.b.toInt();
    }
  }
  return out;
}

double _mad(Uint8List a, Uint8List b) {
  final img.Image? ia = img.decodePng(a);
  final img.Image? ib = img.decodePng(b);
  if (ia == null || ib == null) {
    return _madRaw(a, b);
  }
  int n = ia.width * ia.height * 3;
  double sum = 0;
  int count = 0;
  for (int y = 0; y < ia.height && y < ib.height; y++) {
    for (int x = 0; x < ia.width && x < ib.width; x++) {
      final pa = ia.getPixel(x, y);
      final pb = ib.getPixel(x, y);
      sum += (pa.r.toInt() - pb.r.toInt()).abs();
      sum += (pa.g.toInt() - pb.g.toInt()).abs();
      sum += (pa.b.toInt() - pb.b.toInt()).abs();
      count += 3;
    }
  }
  return count == 0 ? 0 : sum / count;
}

double _madRaw(Uint8List a, Uint8List b) {
  int n = a.length < b.length ? a.length : b.length;
  double sum = 0;
  for (int i = 0; i < n; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / n;
}

Uint8List _rgbFromPng(Uint8List png) {
  final img.Image? im = img.decodePng(png);
  if (im == null) return png;
  final Uint8List out = Uint8List(im.width * im.height * 3);
  for (int y = 0; y < im.height; y++) {
    for (int x = 0; x < im.width; x++) {
      final img.Pixel p = im.getPixel(x, y);
      final int idx = (y * im.width + x) * 3;
      out[idx] = p.r.toInt();
      out[idx + 1] = p.g.toInt();
      out[idx + 2] = p.b.toInt();
    }
  }
  return out;
}
