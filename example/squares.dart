import 'dart:html';
import 'dart:typed_data';
import 'dart:async' as async;
import "package:gifencoder/gifencoder.dart" as gifencoder;

const size = 200;
const frameCount = 32;
const framesPerSecond = 15;

drawSquare(CanvasRenderingContext2D ctx, int frameNumber) {
  var frameFraction = (frameNumber / frameCount);
  var green = 0;
  var blue = 0;
  for (var i = 0; i < size/2; i++) {
    var drawnFraction = i / (size/2);
    var red = (256 * (frameFraction + drawnFraction)).floor() % 256;
    ctx.fillStyle = "rgb(${red},${green},${blue})";  
    ctx.fillRect(i, i, size - i*2, size - i*2);  
  }  
}

async.Future<String> createDataUrl(Uint8List bytes) {
  var c = new async.Completer();
  var f = new FileReader();
  f.onLoadEnd.listen((ProgressEvent e) {
    if (f.readyState == FileReader.DONE) {
      String url = f.result;
      c.complete(url.replaceFirst("data:;", "data:image/gif;"));
    }    
  });
  f.readAsDataUrl(new Blob([bytes]));
  return c.future;
}

main() {
  var ctx = new CanvasElement(width: size, height: size).context2D;
  var frames = new gifencoder.GifBuffer(size, size);
  for (var i = 0; i < frameCount; i++) {
    drawSquare(ctx, i);
    frames.add(ctx.getImageData(0, 0, size, size).data);
  }
  Uint8List gif = frames.build(framesPerSecond);
  createDataUrl(gif).then((dataUrl) {
    ImageElement elt = query("#gif");
    elt.src = dataUrl;  
  });
}
