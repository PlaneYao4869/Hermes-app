import 'dart:async';
import 'package:nsd/nsd.dart';

class DiscoveredService {
  final String name;
  final String host;
  final int port;
  final Map<String, String> txt;

  const DiscoveredService({
    required this.name,
    required this.host,
    required this.port,
    this.txt = const {},
  });
}

class MdnsDiscovery {
  static const _serviceType = '_hermes._tcp';

  /// Discover Hermes Gateway services on the local network
  static Future<List<DiscoveredService>> discover({Duration timeout = const Duration(seconds: 5)}) async {
    final completer = Completer<List<DiscoveredService>>();
    final services = <DiscoveredService>[];
    Discovery? discovery;

    try {
      discovery = await startDiscovery(_serviceType);

      discovery.addServiceListener((service, status) {
        if (status == ServiceStatus.found) {
          final discovered = DiscoveredService(
            name: service.name ?? 'Hermes Gateway',
            host: service.host ?? '',
            port: service.port ?? 8642,
          );
          services.add(discovered);
        }
      });

      Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(services);
        }
      });
    } catch (e) {
      if (!completer.isCompleted) {
        completer.complete(services);
      }
    }

    return completer.future;
  }
}
