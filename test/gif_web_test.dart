library gif_web_test;

import 'package:unittest/unittest.dart';
import 'package:unittest/html_config.dart';
import 'dart:html';
import '../lib/gif.dart' as gif;

main() {
  useHtmlConfiguration();
  
  test('one black pixel', () {
    var ctx = new CanvasElement(width: 1, height: 1).context2D ..fillStyle = "black" ..fillRect(0, 0, 1, 1);
    var data = ctx.getImageData(0, 0, 1, 1);
    var blob = new Blob([new gif.IndexedImage(data.width, data.height, data.data).encodeGif()]);
    
    var f = new FileReader();
    
    loadedDataUrl(ProgressEvent e) {
      expect(f.error, null);
      expect(f.readyState, FileReader.DONE);
      String url = f.result;
      expect(url, startsWith("data:;"));
      url = url.replaceFirst("data:;", "data:image/gif;");
      var img = new ImageElement(src: url);
      img.onLoad.listen(expectAsync1((e) {
        expect(img.width, 1);
        expect(img.height, 1);
        checkPixel(img, 0, 0, [0, 0, 0, 255]);        
      }));
    }
    
    f.onLoadEnd.listen(expectAsync1(loadedDataUrl));
    f.readAsDataUrl(blob);
  });
}

checkPixel(ImageElement img, int x, int y, List<int> expectedRGBA) {
  var ctx = new CanvasElement(width: x + 1, height: y + 1).context2D ..fillStyle = "white" ..fillRect(0, 0, x + 1, y + 1);
  ctx.drawImage(img, 0, 0);
  var data = ctx.getImageData(0, 0, 1, 1).data;
  expect(data, expectedRGBA);         
}
