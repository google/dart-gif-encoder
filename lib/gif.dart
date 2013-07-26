library gif;

import "dart:typed_data";

// Spec: http://www.w3.org/Graphics/GIF/spec-gif89a.txt
// Explanation: http://www.matthewflickinger.com/lab/whatsinagif/bits_and_bytes.asp
// Also see: http://en.wikipedia.org/wiki/File:Quilt_design_as_46x46_uncompressed_GIF.gif

const maxColorBits = 7;
const maxColors = 1<<maxColorBits;

/// An image with a restricted palette.
class IndexedImage {
  final int width;
  final int height;
  final colors = new ColorTable();
  List<int> pixels;

  /**
   * Builds an indexed image from per-pixel rgba data, ignoring the alpha channel.
   * Throws an exception if the the image has too many colors.
   * (The input format is the same used by the ImageData class, which can be created
   * from a canvas element.)
   */
  IndexedImage(this.width, this.height, List<int> rgba) {   
    pixels = colors.indexImage(width, height, rgba);    
    colors.finish();
  }
  
  /**
   * Converts the image into a GIF, represented as a list of bytes.
   */
  Uint8List encodeGif() {
    return new Uint8List.fromList(
        _header(width, height, colors.bits)
        ..addAll(colors.table)
        ..addAll(_startImage(0, 0, width, height))
        ..addAll(_pixels(pixels, colors.bits))
        ..addAll(_trailer()));
  }
}

class IndexedAnimation {
  final int width;
  final int height;
  final colors = new ColorTable();
  final frames = new List<List<int>>();
  
  IndexedAnimation(this.width, this.height, List<List<int>> rgbaFrames) {
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
        ..addAll(_pixels(frame, colors.bits));
    }
    bytes.addAll(_trailer());
    return new Uint8List.fromList(bytes);
  }
}

class ColorTable {
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

/**
 * Compresses the pixels using LZW.
 */
List<int> _pixels(List<int> pixels, int colorBits) {
  CodeBook book = new CodeBook(colorBits);
  CodeBuffer buf = new CodeBuffer(book);
  
  buf.add(book.clearCode);
  if (pixels.isEmpty) {
    buf.add(book.endCode);
    return buf.finish();    
  }
  
  int code = pixels[0];
  for (int px in pixels.sublist(1)) {
    int newCode = book.codeAfterAppend(code, px);
    if (newCode == null) {
      buf.add(code);
      book.define(code, px);
      code = px;
    } else {
      code = newCode;
    }
  }
  buf.add(code);    
  buf.add(book.endCode);
  return buf.finish();
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

// The highest code that can be defined in the CodeBook.
const maxCode = (1 << 12) - 1;

/**
 * A CodeBook contains codes defined during LZW compression. It's a mapping from a string
 * of pixels to the code that represents it. The codes are stored in a trie which is
 * represented as a map. Codes may be up to 12 bits. The size of the codebook is always
 * the minimum power of 2 needed to represent all the codes and automatically increases
 * as new codes are defined.
 */
class CodeBook {
  int colorBits;
  // The "clear" code which resets the table.
  int clearCode;
  // The "end of data" code.
  int endCode;

  // A mapping from (c1, pixel) -> c2 that returns the new code for the pixel string
  // formed by appending a pixel to the end of c1's pixel string. (In addition, the
  // codes for single pixels are stored in the map with c1 set to 0.)
  // The key is encoded by shifting c1 to the left by eight bits and adding the pixel,
  // forming a 20-bit number.
  Map<int, int> _codeAfterAppend;

  // Codes from this value and above are not yet defined.
  int nextUnused;
  
  // The number of bits required to represent every code.
  int bitsPerCode;
  
  // The current size of the codebook.
  int size;
  
  CodeBook(this.colorBits) {
    if (colorBits < 2) {
      colorBits = 2;
    }
    assert(colorBits <= 8);
    clearCode = 1 << colorBits;
    endCode = clearCode + 1;
    clear();
  }
  
  void clear() {
    _codeAfterAppend = new Map<int, int>();
    nextUnused = endCode + 1;
    bitsPerCode = colorBits + 1;
    size = 1 << bitsPerCode;
  }
  
  /**
   * Returns the new code after appending a pixel to the pixel string represented by the previous code,
   * or null if the code isn't in the table.
   */
  int codeAfterAppend(int code, int pixelIndex) {
   return _codeAfterAppend[(code << 8) | pixelIndex];
  }

  /**
   * Defines a new code to be the pixel string of a previous code with one pixel appended.
   * Returns true if defined, or false if there's no more room in the table.
   */
  bool define(int code, int pixelIndex) {
    if (nextUnused == maxCode) {
      return false;
    }
    _codeAfterAppend[(code << 8) | pixelIndex] = nextUnused++;
    if (nextUnused > size) {
      bitsPerCode++;
      size = 1 << bitsPerCode;
    }
    return true;
  }
}

/// Writes a sequence of integers using a variable number of bits, for LZW compression.
class CodeBuffer {
  final CodeBook book;
  final finishedBytes = new List<int>();
  // A buffer containing bits not yet added to finishedBytes.
  int buf = 0;
  // Number of bits in the buffer.
  int bits = 0;

  CodeBuffer(this.book);
  
  void add(int code) {
    assert(code >= 0 && code < book.size);
    buf |= (code << bits);
    bits += book.bitsPerCode;
    while (bits >= 8) {
      finishedBytes.add(buf & 0xFF);
      buf = buf >> 8;
      bits -= 8;
    }
  }
  
  List<int> finish() {
    // Add the remaining bits. (Unused bits are set to zero.)
    if (bits > 0) {
      finishedBytes.add(buf);
    }
    
    // The final result starts withe the number of color bits.
    final dest = new List<int>();
    dest.add(book.colorBits);

    // Divide it up into blocks with a size in front of each block.
    int len = finishedBytes.length;
    for (int i = 0; i < len;) {
      if (len - i >= 255) {
        dest.add(255);
        dest.addAll(finishedBytes.sublist(i, i + 255));
        i += 255;
      } else {
        dest.add(len - i);
        dest.addAll(finishedBytes.sublist(i, len));
        i = len;
      }
    }
    dest.add(0);
    return dest;
  }
}
