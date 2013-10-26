A gif encoder written in Dart.

Usage
-----

To create a regular GIF:
```dart
import 'dart:html';
import 'package:gifencoder/gifencoder.dart';
  
int width = ...;
int height = ...;

var ctx = new CanvasElement(width: width, height: height).context2D;

// draw your image in the canvas context
var data = ctx.getImageData(0, 0, width, height);
List<int> bytes = gifencoder.makeGif(width, height, data.data)
```  
To create an animated Gif, use a GifBuffer instead:
```dart
int framesPerSecond = ...;
var frames = new gifencoder.GifBuffer(width, height);

for (var i = 0; i < myFrameCount; i++) {
    // draw the next frame on the canvas context
    frames.add(ctx.getImageData(0, 0, width, height).data);
}

List<int> bytes = frames.build(framesPerSecond);
```
Once you have the bytes of the GIF, you can save it somewhere or convert it into a data URL.
See example/squares.dart for how to do that.
