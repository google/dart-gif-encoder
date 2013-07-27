library gifencoder;

import "dart:typed_data";
import "src/lzw.dart" as lzw;

// Spec: http://www.w3.org/Graphics/GIF/spec-gif89a.txt
// Explanation: http://www.matthewflickinger.com/lab/whatsinagif/bits_and_bytes.asp
// Also see: http://en.wikipedia.org/wiki/File:Quilt_design_as_46x46_uncompressed_GIF.gif

/**
 * Creates a GIF from per-pixel rgba data, ignoring the alpha channel.
 * Returns a list of bytes. Throws an exception if the the image has too
 * many colors.
 * 
 * (The input format is the same as the "data" field of the html.ImageData class,
 * which can be created from a canvas element.)
 */
Uint8List makeGif(int width, int height, List<int> rgba) {
  return new _IndexedImage(width, height, rgba).encodeGif();  
}

/**
 * An incomplete GIF animation.
 */
class GifBuffer {
  final int width;
  final int height;
  final List<List<int>> _frames = new List<List<int>>();
  
  /// Creates an animation of the specified width and height, with zero frames.
  GifBuffer(this.width, this.height);
  
  /**
   * Adds a frame to the animation. The pixels are specified as rgba data but the alpha channel is
   * ignored.
   */
  void add(List<int> rgba) {
    _frames.add(rgba);  
  }
  
  /// Returns the bytes of an animated GIF.
  Uint8List build(int framesPerSecond) {
    return new _IndexedAnimation(width, height, _frames).encodeGif(framesPerSecond); 
  }
}

const maxColorBits = 7;
const maxColors = 1<<maxColorBits;

class _IndexedImage {
  final int width;
  final int height;
  final colors = new _ColorTable();
  List<int> pixels;

  _IndexedImage(this.width, this.height, List<int> rgba) {   
    pixels = colors.indexImage(width, height, rgba);    
    colors.finish();
  }

  Uint8List encodeGif() {
    return new Uint8List.fromList(
        _header(width, height, colors.bits)
        ..addAll(colors.table)
        ..addAll(_startImage(0, 0, width, height))
        ..addAll(lzw.compress(pixels, colors.bits))
        ..addAll(_trailer()));
  }
}

/// An animation with a restricted palette.
class _IndexedAnimation {
  final int width;
  final int height;
  final colors = new _ColorTable();
  final frames = new List<List<int>>();

  /**
   * Builds an indexed image from a set of frames. Each frame contains rgba data for the pixels,
   * but the alpha channel is ignored.
   * Throws an exception if the the image has too many colors.
   * (The input format is the same used by the ImageData class, which can be created
   * from a canvas element.)
   */
  _IndexedAnimation(this.width, this.height, Iterable<List<int>> rgbaFrames) {
    for (var frame in rgbaFrames) {
      frames.add(colors.indexImage(width, height, frame));      
    }
    colors.finish();
  }

  /**
   * Converts the animation into an uncompressed GIF, represented as a list of bytes.
   */
  Uint8List encodeGif(int fps) {
    int delay = 100 ~/ fps;
    if (delay < 6) {
      delay = 6; // http://nullsleep.tumblr.com/post/16524517190/animated-gif-minimum-frame-delay-browser-compatibility
    }
    
    List<int> bytes = _header(width, height, colors.bits);
    bytes.addAll(colors.table);
    bytes.addAll(_loop(0));
    
    for (int i = 0; i < frames.length; i++) {
      var frame = frames[i];
      bytes
        ..addAll(_delayNext(delay))
        ..addAll(_startImage(0, 0, width, height))
        ..addAll(lzw.compress(frame, colors.bits));
    }
    bytes.addAll(_trailer());
    return new Uint8List.fromList(bytes);
  }
}

class _ColorTable {
  final List<int> table = new List<int>();
  final colorToIndex = new Map<int, int>();
  int bits;
  
  /**
   *  Given rgba data, add each color to the color table.
   *  Returns the same pixels as color indexes.
   *  Throws an exception if we run out of colors.
   */
  List<int> indexImage(int width, int height, List<int> rgba) {
    var pixels = new List<int>(width * height);      
    assert(pixels.length == rgba.length / 4);
    for (int i = 0; i < rgba.length; i += 4) {
      int color = rgba[i] << 16 | rgba[i+1] << 8 | rgba[i+2];
      int index = colorToIndex[color];
      if (index == null) {
        if (colorToIndex.length == maxColors) {
          throw new Exception("image has more than ${maxColors} colors");
        }
        index = table.length ~/ 3;
        colorToIndex[color] = index;
        table..add(rgba[i])..add(rgba[i+1])..add(rgba[i+2]);
      }
      pixels[i>>2] = index;
    }  
    return pixels;
  }
  
  /**
   * Pads the color table with zeros to the next power of 2 and sets bits.
   */
  void finish() {
    for (int bits = 1;; bits++) {
      int colors = 1 << bits;
      if (colors * 3 >= table.length) {
        while (table.length < colors * 3) {
          table..add(0);
        }
        this.bits = bits;
        return;
      }
    }
  }
  
  int get numColors {
    return table.length ~/ 3;
  }
}

List<int> _header(int width, int height, int colorBits) {
  const _headerBlock = const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]; // GIF 89a
  
  List<int> bytes = [];
  bytes.addAll(_headerBlock);
  _addShort(bytes, width);
  _addShort(bytes, height);
  bytes..add(0xF0 | colorBits - 1)..add(0)..add(0);
  return bytes;
}

// See: http://odur.let.rug.nl/~kleiweg/gif/netscape.html
List<int> _loop(int reps) {
  List<int> bytes = [0x21, 0xff, 0x0B];
  bytes.addAll("NETSCAPE2.0".codeUnits);
  bytes.addAll([3, 1]);
  _addShort(bytes, reps);
  bytes.add(0);
  return bytes;
}

List<int> _delayNext(int centiseconds) {
  var bytes = [0x21, 0xF9, 4, 0];
  _addShort(bytes, centiseconds);
  bytes..add(0)..add(0);
  return bytes;
}

List<int> _startImage(int left, int top, int width, int height) {
  List<int> bytes = [0x2C];
  _addShort(bytes, left);
  _addShort(bytes, top);
  _addShort(bytes, width);
  _addShort(bytes, height);
  bytes.add(0); 
  return bytes;
}

List<int> _trailer() {
  return [0x3b];
}

void _addShort(List<int> dest, int n) {
  if (n < 0 || n > 0xFFFF) {
    throw new Exception("out of range for short: ${n}");
  }
  dest..add(n & 0xff)..add(n >> 8);
}


