import 'dart:isolate';

import 'package:dart_periphery/dart_periphery.dart';
import 'package:logging/logging.dart';

final log = Logger('GPIO');

class GPIOClient {
  late List<GPIO> gpios;

  GPIOClient.init() {
    var clk = GPIO(17, GPIOdirection.gpioDirIn);
    clk.setGPIOedge(GPIOedge.gpioEdgeBoth);
    var dt = GPIO(18, GPIOdirection.gpioDirIn);
    dt.setGPIOedge(GPIOedge.gpioEdgeBoth);
    log.info('CLK info: ${clk.getGPIOinfo()}');
    log.info('DT info: ${dt.getGPIOinfo()}');
    gpios = List.unmodifiable([clk, dt]);
    handle();
  }

  void close() {
    for (final gpio in gpios) {
      gpio.dispose();
    }
  }

  Future<void> handle() async {
    return await Isolate.run(() async {
      for (;;) {
        var poll = GPIO.pollMultiple(gpios, -1);
        if (poll.eventCounter > 0) {
          for (var i = 0; i < gpios.length; i++) {
            if (poll.eventOccurred.elementAt(i)) {
              var event = gpios.elementAt(i).readEvent();
              log.info('PIN $i = ${event.edge.name}');
            }
          }
        }
      }
    });
  }
}
