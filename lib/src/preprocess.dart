import 'dart:typed_data';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'constants.dart';

class Processed640 {
  Processed640({
    required this.processedRgbUint8,
    required this.yoloInputFloat,
    required this.origW,
    required this.origH,
    required this.focusScore,
  });

  final Uint8List processedRgbUint8;
  final Float32List yoloInputFloat;
  final int origW;
  final int origH;
  final double focusScore;
}

class Preprocessor {
  static Processed640 processOnce(Uint8List jpeg) {
    final img.Image? decoded = img.decodeImage(jpeg);
    if (decoded == null) {
      throw Exception('decodeImage failed');
    }
    final img.Image oriented = img.bakeOrientation(decoded);
    final int origW = oriented.width;
    final int origH = oriented.height;

    img.Image stretched = img.copyResize(
      oriented,
      width: kDetectSize,
      height: kDetectSize,
      interpolation: img.Interpolation.average,
    );

    final double focusScore = _varianceOfLaplacianGray(stretched);

    Uint8List rgb = _imageToRgbUint8(stretched);
    rgb = _grayWorldWhiteBalance(rgb);
    rgb = _claheLab(rgb);
    rgb = _unsharpMask(rgb);

    final Float32List yoloInput = Float32List(
      1 * 3 * kDetectSize * kDetectSize,
    );
    for (int y = 0; y < kDetectSize; y++) {
      for (int x = 0; x < kDetectSize; x++) {
        final int idx = (y * kDetectSize + x) * 3;
        final double r = rgb[idx] / 255.0;
        final double g = rgb[idx + 1] / 255.0;
        final double b = rgb[idx + 2] / 255.0;
        yoloInput[0 * kDetectSize * kDetectSize + y * kDetectSize + x] = r;
        yoloInput[1 * kDetectSize * kDetectSize + y * kDetectSize + x] = g;
        yoloInput[2 * kDetectSize * kDetectSize + y * kDetectSize + x] = b;
      }
    }

    return Processed640(
      processedRgbUint8: rgb,
      yoloInputFloat: yoloInput,
      origW: origW,
      origH: origH,
      focusScore: focusScore,
    );
  }

  static Uint8List _imageToRgbUint8(img.Image image) {
    final Uint8List out = Uint8List(kDetectSize * kDetectSize * 3);
    for (int y = 0; y < kDetectSize; y++) {
      for (int x = 0; x < kDetectSize; x++) {
        final img.Pixel p = image.getPixel(x, y);
        final int idx = (y * kDetectSize + x) * 3;
        out[idx] = p.r.toInt().clamp(0, 255);
        out[idx + 1] = p.g.toInt().clamp(0, 255);
        out[idx + 2] = p.b.toInt().clamp(0, 255);
      }
    }
    return out;
  }

  static Uint8List _grayWorldWhiteBalance(Uint8List rgb) {
    double mr = 0, mg = 0, mb = 0;
    final int total = kDetectSize * kDetectSize;
    for (int i = 0; i < total; i++) {
      mr += rgb[i * 3 + 0];
      mg += rgb[i * 3 + 1];
      mb += rgb[i * 3 + 2];
    }
    mr /= total;
    mg /= total;
    mb /= total;
    final double m = (mr + mg + mb) / 3.0;
    if (mr == 0 || mg == 0 || mb == 0) return Uint8List.fromList(rgb);
    final Uint8List out = Uint8List(total * 3);
    for (int i = 0; i < total; i++) {
      double r = rgb[i * 3 + 0] * (m / mr);
      double g = rgb[i * 3 + 1] * (m / mg);
      double b = rgb[i * 3 + 2] * (m / mb);
      out[i * 3 + 0] = r.floor().clamp(0, 255);
      out[i * 3 + 1] = g.floor().clamp(0, 255);
      out[i * 3 + 2] = b.floor().clamp(0, 255);
    }
    return out;
  }

  static void _rgbToXyz(double r, double g, double b, List<double> out) {
    double R = r > 0.04045
        ? math.pow((r + 0.055) / 1.055, 2.4).toDouble()
        : r / 12.92;
    double G = g > 0.04045
        ? math.pow((g + 0.055) / 1.055, 2.4).toDouble()
        : g / 12.92;
    double B = b > 0.04045
        ? math.pow((b + 0.055) / 1.055, 2.4).toDouble()
        : b / 12.92;
    out[0] = R * 0.4124564 + G * 0.3575761 + B * 0.1804375;
    out[1] = R * 0.2126729 + G * 0.7151522 + B * 0.0721750;
    out[2] = R * 0.0193339 + G * 0.1191920 + B * 0.9503041;
  }

  static void _xyzToRgb(double x, double y, double z, List<double> out) {
    double R = x * 3.2404542 + y * -1.5371385 + z * -0.4985314;
    double G = x * -0.9692660 + y * 1.8760108 + z * 0.0415560;
    double B = x * 0.0556434 + y * -0.2040259 + z * 1.0572252;
    R = R > 0.0031308
        ? 1.055 * math.pow(R, 1.0 / 2.4).toDouble() - 0.055
        : 12.92 * R;
    G = G > 0.0031308
        ? 1.055 * math.pow(G, 1.0 / 2.4).toDouble() - 0.055
        : 12.92 * G;
    B = B > 0.0031308
        ? 1.055 * math.pow(B, 1.0 / 2.4).toDouble() - 0.055
        : 12.92 * B;
    out[0] = R.clamp(0.0, 1.0);
    out[1] = G.clamp(0.0, 1.0);
    out[2] = B.clamp(0.0, 1.0);
  }

  static void _xyzToLab(double x, double y, double z, List<double> out) {
    const double xn = 0.95047, yn = 1.0, zn = 1.08883;
    double fx = x / xn;
    double fy = y / yn;
    double fz = z / zn;
    fx = fx > 0.008856
        ? math.pow(fx, 1.0 / 3.0).toDouble()
        : (7.787 * fx + 16.0 / 116.0);
    fy = fy > 0.008856
        ? math.pow(fy, 1.0 / 3.0).toDouble()
        : (7.787 * fy + 16.0 / 116.0);
    fz = fz > 0.008856
        ? math.pow(fz, 1.0 / 3.0).toDouble()
        : (7.787 * fz + 16.0 / 116.0);
    out[0] = 116.0 * fy - 16.0;
    out[1] = 500.0 * (fx - fy);
    out[2] = 200.0 * (fy - fz);
  }

  static void _labToXyz(double L, double a, double b, List<double> out) {
    const double xn = 0.95047, yn = 1.0, zn = 1.08883;
    double fy = (L + 16.0) / 116.0;
    double fx = fy + a / 500.0;
    double fz = fy - b / 200.0;
    double fx3 = fx * fx * fx;
    double fy3 = fy * fy * fy;
    double fz3 = fz * fz * fz;
    if (fx3 > 0.008856) {
      fx = fx3;
    } else {
      fx = (fx - 16.0 / 116.0) / 7.787;
    }
    if (fy3 > 0.008856) {
      fy = fy3;
    } else {
      fy = (fy - 16.0 / 116.0) / 7.787;
    }
    if (fz3 > 0.008856) {
      fz = fz3;
    } else {
      fz = (fz - 16.0 / 116.0) / 7.787;
    }
    out[0] = fx * xn;
    out[1] = fy * yn;
    out[2] = fz * zn;
  }

  static Uint8List _claheLab(Uint8List rgb) {
    final int size = kDetectSize;
    final int tiles = kClaheTiles;
    final List<double> A = List.filled(size * size, 0.0);
    final List<double> B = List.filled(size * size, 0.0);
    final List<double> xyz = List.filled(3, 0.0);
    final List<double> labv = List.filled(3, 0.0);
    final List<double> lightness = List.filled(size * size, 0.0);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final int idx = (y * size + x) * 3;
        final double r = rgb[idx] / 255.0;
        final double g = rgb[idx + 1] / 255.0;
        final double b = rgb[idx + 2] / 255.0;
        _rgbToXyz(r, g, b, xyz);
        _xyzToLab(xyz[0], xyz[1], xyz[2], labv);
        lightness[y * size + x] = labv[0];
        A[y * size + x] = labv[1];
        B[y * size + x] = labv[2];
      }
    }
    final List<int> lightness8 = List.filled(size * size, 0);
    for (int i = 0; i < size * size; i++) {
      lightness8[i] = (lightness[i] * 255.0 / 100.0).round().clamp(0, 255);
    }
    final List<int> equalizedLightness = _claheOnUint8(
      lightness8,
      size,
      size,
      tiles,
      kClaheClip,
    );
    final Uint8List out = Uint8List(size * size * 3);
    final List<double> xyz2 = List.filled(3, 0.0);
    final List<double> rgb2 = List.filled(3, 0.0);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final int i = y * size + x;
        final double newLightness = equalizedLightness[i] * 100.0 / 255.0;
        _labToXyz(newLightness, A[i], B[i], xyz2);
        _xyzToRgb(xyz2[0], xyz2[1], xyz2[2], rgb2);
        final int idx = i * 3;
        out[idx] = (rgb2[0] * 255.0).round().clamp(0, 255);
        out[idx + 1] = (rgb2[1] * 255.0).round().clamp(0, 255);
        out[idx + 2] = (rgb2[2] * 255.0).round().clamp(0, 255);
      }
    }
    return out;
  }

  static List<int> _claheOnUint8(
    List<int> src,
    int w,
    int h,
    int tiles,
    double clipLimit,
  ) {
    final int tileW = w ~/ tiles;
    final int tileH = h ~/ tiles;
    final int tileArea = tileW * tileH;
    final int clipVal = (clipLimit * tileArea / 256.0).toInt();
    final List<List<int>> tileLut = List.generate(
      tiles * tiles,
      (_) => List.filled(256, 0),
    );
    for (int ty = 0; ty < tiles; ty++) {
      for (int tx = 0; tx < tiles; tx++) {
        final List<int> hist = List.filled(256, 0);
        for (int y = 0; y < tileH; y++) {
          for (int x = 0; x < tileW; x++) {
            final int px = tx * tileW + x;
            final int py = ty * tileH + y;
            hist[src[py * w + px]]++;
          }
        }
        int clipped = 0;
        for (int i = 0; i < 256; i++) {
          if (hist[i] > clipVal) {
            clipped += (hist[i] - clipVal);
            hist[i] = clipVal;
          }
        }
        int redist = clipped ~/ 256;
        int residual = clipped % 256;
        for (int i = 0; i < 256; i++) {
          hist[i] += redist;
        }
        int step = residual == 0 ? 256 : (256 ~/ residual);
        if (step < 1) step = 1;
        for (int i = 0; i < residual; i++) {
          hist[(i * step) % 256]++;
        }
        final List<int> lut = tileLut[ty * tiles + tx];
        int sum = 0;
        for (int i = 0; i < 256; i++) {
          sum += hist[i];
          lut[i] = ((sum * 255.0) / tileArea).round().clamp(0, 255);
        }
      }
    }
    final List<int> dst = List.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double txf = (x.toDouble() / tileW) - 0.5;
        double tyf = (y.toDouble() / tileH) - 0.5;
        int x1 = txf.floor();
        int y1 = tyf.floor();
        int x2 = x1 + 1;
        int y2 = y1 + 1;
        final double dx = txf - x1;
        final double dy = tyf - y1;
        if (x1 < 0) x1 = 0;
        if (y1 < 0) y1 = 0;
        if (x2 >= tiles) x2 = tiles - 1;
        if (y2 >= tiles) y2 = tiles - 1;
        if (x1 >= tiles) x1 = tiles - 1;
        if (y1 >= tiles) y1 = tiles - 1;
        final int val = src[y * w + x];
        final List<int> lut1 = tileLut[y1 * tiles + x1];
        final List<int> lut2 = tileLut[y1 * tiles + x2];
        final List<int> lut3 = tileLut[y2 * tiles + x1];
        final List<int> lut4 = tileLut[y2 * tiles + x2];
        final double v1 =
            lut1[val].toDouble() * (1 - dx) + lut2[val].toDouble() * dx;
        final double v2 =
            lut3[val].toDouble() * (1 - dx) + lut4[val].toDouble() * dx;
        final double res = v1 * (1 - dy) + v2 * dy;
        dst[y * w + x] = res.round().clamp(0, 255);
      }
    }
    return dst;
  }

  static Uint8List _gaussianBlurUint8(Uint8List src, int radius, double sigma) {
    final int size = kDetectSize;
    final int ksize = radius * 2 + 1;
    final List<double> kernel = List.filled(ksize, 0.0);
    double sumk = 0;
    for (int i = 0; i < ksize; i++) {
      final double x = (i - radius).toDouble();
      kernel[i] = math.exp(-(x * x) / (2.0 * sigma * sigma));
      sumk += kernel[i];
    }
    for (int i = 0; i < ksize; i++) {
      kernel[i] /= sumk;
    }
    Uint8List tmp = Uint8List(size * size * 3);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        double r = 0, g = 0, b = 0;
        for (int kx = 0; kx < ksize; kx++) {
          int sx = x + (kx - radius);
          if (sx < 0) sx = -sx;
          if (sx >= size) sx = 2 * size - 2 - sx;
          final int sidx = (y * size + sx) * 3;
          r += src[sidx + 0] * kernel[kx];
          g += src[sidx + 1] * kernel[kx];
          b += src[sidx + 2] * kernel[kx];
        }
        final int tidx = (y * size + x) * 3;
        tmp[tidx + 0] = r.round().clamp(0, 255);
        tmp[tidx + 1] = g.round().clamp(0, 255);
        tmp[tidx + 2] = b.round().clamp(0, 255);
      }
    }
    Uint8List out = Uint8List(size * size * 3);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        double r = 0, g = 0, b = 0;
        for (int ky = 0; ky < ksize; ky++) {
          int sy = y + (ky - radius);
          if (sy < 0) sy = -sy;
          if (sy >= size) sy = 2 * size - 2 - sy;
          final int sidx = (sy * size + x) * 3;
          r += tmp[sidx + 0] * kernel[ky];
          g += tmp[sidx + 1] * kernel[ky];
          b += tmp[sidx + 2] * kernel[ky];
        }
        final int oidx = (y * size + x) * 3;
        out[oidx + 0] = r.round().clamp(0, 255);
        out[oidx + 1] = g.round().clamp(0, 255);
        out[oidx + 2] = b.round().clamp(0, 255);
      }
    }
    return out;
  }

  static Uint8List _unsharpMask(Uint8List rgb) {
    final int size = kDetectSize;
    final Uint8List blurred = _gaussianBlurUint8(rgb, 3, kUnsharpSigma);
    final Uint8List out = Uint8List(size * size * 3);
    for (int i = 0; i < size * size; i++) {
      double r = 1.4 * rgb[i * 3 + 0] - 0.4 * blurred[i * 3 + 0];
      double g = 1.4 * rgb[i * 3 + 1] - 0.4 * blurred[i * 3 + 1];
      double b = 1.4 * rgb[i * 3 + 2] - 0.4 * blurred[i * 3 + 2];
      out[i * 3 + 0] = r.round().clamp(0, 255);
      out[i * 3 + 1] = g.round().clamp(0, 255);
      out[i * 3 + 2] = b.round().clamp(0, 255);
    }
    return out;
  }

  static double _varianceOfLaplacianGray(img.Image image) {
    final int size = kDetectSize;
    final List<int> gray = List.filled(size * size, 0);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final img.Pixel p = image.getPixel(x, y);
        gray[y * size + x] =
            (4899 * p.r.toInt() +
                9617 * p.g.toInt() +
                1868 * p.b.toInt() +
                8192) >>
            14;
      }
    }
    double meanv = 0;
    final List<double> lap = List.filled(size * size, 0.0);
    for (int y = 0; y < size; y++) {
      final int above = y == 0 ? 1 : y - 1;
      final int below = y == size - 1 ? size - 2 : y + 1;
      for (int x = 0; x < size; x++) {
        final int left = x == 0 ? 1 : x - 1;
        final int right = x == size - 1 ? size - 2 : x + 1;
        final double value =
            -4.0 * gray[y * size + x] +
            gray[above * size + x] +
            gray[below * size + x] +
            gray[y * size + left] +
            gray[y * size + right];
        lap[y * size + x] = value;
        meanv += value;
      }
    }
    meanv /= (size * size);
    double varv = 0;
    for (final double value in lap) {
      final double difference = value - meanv;
      varv += difference * difference;
    }
    varv /= (size * size);
    return varv;
  }

  static double focusScoreOfImage(img.Image image) {
    return _varianceOfLaplacianGray(image);
  }

  static Uint8List grayWorldWhiteBalanceOnly(Uint8List rgb) {
    return _grayWorldWhiteBalance(rgb);
  }

  static Uint8List claheLabOnly(Uint8List rgb) {
    return _claheLab(rgb);
  }

  static Uint8List unsharpMaskOnly(Uint8List rgb) {
    return _unsharpMask(rgb);
  }

  static Uint8List cropFromProcessed640(
    Uint8List processedRgb, {
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  }) {
    final int size = kDetectSize;
    final double marginX = (x2 - x1) * kCropMargin / 2;
    final double marginY = (y2 - y1) * kCropMargin / 2;
    int cx1 = (x1 - marginX).toInt();
    int cy1 = (y1 - marginY).toInt();
    int cx2 = (x2 + marginX).toInt();
    int cy2 = (y2 + marginY).toInt();
    cx1 = cx1.clamp(0, size - 1);
    cy1 = cy1.clamp(0, size - 1);
    cx2 = cx2.clamp(0, size);
    cy2 = cy2.clamp(0, size);
    if (cx2 <= cx1 || cy2 <= cy1) throw Exception('empty crop');
    int cw = cx2 - cx1;
    int ch = cy2 - cy1;
    int side = cw > ch ? cw : ch;
    final int padX = (side - cw) ~/ 2;
    final int padY = (side - ch) ~/ 2;
    final Uint8List square = Uint8List(side * side * 3);
    for (int y = 0; y < side; y++) {
      for (int x = 0; x < side; x++) {
        int sx = cx1 + x - padX;
        int sy = cy1 + y - padY;
        sx = sx.clamp(cx1, cx2 - 1);
        sy = sy.clamp(cy1, cy2 - 1);
        final int sidx = (sy * size + sx) * 3;
        final int tidx = (y * side + x) * 3;
        square[tidx + 0] = processedRgb[sidx + 0];
        square[tidx + 1] = processedRgb[sidx + 1];
        square[tidx + 2] = processedRgb[sidx + 2];
      }
    }
    return side > kCropSize
        ? _resizeAreaRgb(square, side, kCropSize)
        : _resizeBicubicRgb(square, side, kCropSize);
  }

  static Uint8List _resizeAreaRgb(Uint8List src, int srcSize, int dstSize) {
    final Uint8List dst = Uint8List(dstSize * dstSize * 3);
    final double scale = srcSize / dstSize;
    for (int y = 0; y < dstSize; y++) {
      final double yStart = y * scale;
      final double yEnd = (y + 1) * scale;
      final int firstY = yStart.floor();
      final int lastY = yEnd.ceil();
      for (int x = 0; x < dstSize; x++) {
        final double xStart = x * scale;
        final double xEnd = (x + 1) * scale;
        final int firstX = xStart.floor();
        final int lastX = xEnd.ceil();
        final List<double> sum = <double>[0, 0, 0];
        for (int sy = firstY; sy < lastY; sy++) {
          final double weightY =
              math.min(yEnd, sy + 1.0) - math.max(yStart, sy.toDouble());
          for (int sx = firstX; sx < lastX; sx++) {
            final double weight =
                weightY *
                (math.min(xEnd, sx + 1.0) - math.max(xStart, sx.toDouble()));
            final int srcOffset = (sy * srcSize + sx) * 3;
            for (int channel = 0; channel < 3; channel++) {
              sum[channel] += src[srcOffset + channel] * weight;
            }
          }
        }
        final int dstOffset = (y * dstSize + x) * 3;
        for (int channel = 0; channel < 3; channel++) {
          dst[dstOffset + channel] = (sum[channel] / (scale * scale))
              .round()
              .clamp(0, 255);
        }
      }
    }
    return dst;
  }

  static Uint8List _resizeBicubicRgb(Uint8List src, int srcSize, int dstSize) {
    const double coefficient = -0.75;
    final Uint8List dst = Uint8List(dstSize * dstSize * 3);
    final double scale = srcSize / dstSize;
    for (int y = 0; y < dstSize; y++) {
      final double sourceY = (y + 0.5) * scale - 0.5;
      final int baseY = sourceY.floor();
      for (int x = 0; x < dstSize; x++) {
        final double sourceX = (x + 0.5) * scale - 0.5;
        final int baseX = sourceX.floor();
        final List<double> sum = <double>[0, 0, 0];
        double totalWeight = 0;
        for (int ky = -1; ky <= 2; ky++) {
          final int sy = (baseY + ky).clamp(0, srcSize - 1);
          final double weightY = _cubicWeight(
            sourceY - (baseY + ky),
            coefficient,
          );
          for (int kx = -1; kx <= 2; kx++) {
            final int sx = (baseX + kx).clamp(0, srcSize - 1);
            final double weight =
                weightY * _cubicWeight(sourceX - (baseX + kx), coefficient);
            final int srcOffset = (sy * srcSize + sx) * 3;
            for (int channel = 0; channel < 3; channel++) {
              sum[channel] += src[srcOffset + channel] * weight;
            }
            totalWeight += weight;
          }
        }
        final int dstOffset = (y * dstSize + x) * 3;
        for (int channel = 0; channel < 3; channel++) {
          dst[dstOffset + channel] = (sum[channel] / totalWeight).round().clamp(
            0,
            255,
          );
        }
      }
    }
    return dst;
  }

  static double _cubicWeight(double value, double coefficient) {
    final double x = value.abs();
    if (x <= 1) {
      return (coefficient + 2) * x * x * x - (coefficient + 3) * x * x + 1;
    }
    if (x < 2) {
      return coefficient * x * x * x -
          5 * coefficient * x * x +
          8 * coefficient * x -
          4 * coefficient;
    }
    return 0;
  }
}
